package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"strings"
	"time"

	"github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift/internal/argocd"
	"github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift/internal/drift"
	"github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift/internal/policy"
	"github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift/internal/report"
	"github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift/internal/version"
)

const defaultPolicyPath = "policies/risk.rego"

type argoAPI interface {
	GetApplication(context.Context, string) (*argocd.Application, error)
	GetManagedResources(context.Context, string) (*argocd.ManagedResourcesResponse, error)
}

type findingEvaluator interface {
	EvaluateFinding(context.Context, drift.Finding) ([]policy.Decision, error)
}

type scanDependencies struct {
	newArgoClient func(string, string) (argoAPI, error)
	newEvaluator  func(string) (findingEvaluator, error)
	now           func() time.Time
}

var productionDependencies = scanDependencies{
	newArgoClient: func(serverURL, token string) (argoAPI, error) {
		return argocd.NewClient(serverURL, token)
	},
	newEvaluator: func(policyPath string) (findingEvaluator, error) {
		return policy.NewEvaluator(policyPath)
	},
	now: time.Now,
}

type scanFixture struct {
	Application      *argocd.Application              `json:"application"`
	ManagedResources *argocd.ManagedResourcesResponse `json:"managedResources"`
}

func main() {
	if err := run(os.Args[1:], os.Stdout, os.Stderr, productionDependencies); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run(args []string, stdout, stderr io.Writer, dependencies scanDependencies) error {
	if len(args) == 0 {
		return usageError("command is required")
	}

	switch args[0] {
	case "version":
		_, err := fmt.Fprintf(stdout, "%s %s (%s, %s)\n", version.Name, version.Version, version.Commit, version.Date)
		return err
	case "scan":
		return runScan(args[1:], stdout, stderr, dependencies)
	default:
		return usageError("unknown command " + args[0])
	}
}

func runScan(args []string, stdout, stderr io.Writer, dependencies scanDependencies) error {
	flags := flag.NewFlagSet("scan", flag.ContinueOnError)
	flags.SetOutput(stderr)

	var appName string
	var serverURL string
	var token string
	var output string
	var fixturePath string
	var policyPath string
	var timeout time.Duration

	flags.StringVar(&appName, "app", "", "Argo CD application name")
	flags.StringVar(&serverURL, "server", "", "Argo CD server URL")
	flags.StringVar(&token, "token", "", "Argo CD auth token")
	flags.StringVar(&output, "output", "", "Output format: table or json")
	flags.StringVar(&fixturePath, "fixture", "", "Read a sanitized Application or scan-bundle fixture instead of calling Argo CD")
	flags.StringVar(&policyPath, "policy", "", "OPA/Rego policy path")
	flags.DurationVar(&timeout, "timeout", 30*time.Second, "Overall scan timeout")

	if err := flags.Parse(args); err != nil {
		return err
	}

	serverURL = firstConfigured(serverURL, "ARGOCD_SERVER", "")
	token = firstConfigured(token, "ARGOCD_AUTH_TOKEN", "")
	output = firstConfigured(output, "RADAR_OUTPUT", "table")
	policyPath = firstConfigured(policyPath, "RADAR_POLICY_PATH", defaultPolicyPath)

	output = strings.ToLower(output)
	if output != "table" && output != "json" {
		return usageError("output must be table or json")
	}
	if timeout <= 0 {
		return usageError("timeout must be greater than zero")
	}
	if fixturePath == "" {
		if strings.TrimSpace(appName) == "" {
			return usageError("app is required")
		}
		if strings.TrimSpace(serverURL) == "" {
			return usageError("server is required; pass --server or set ARGOCD_SERVER")
		}
		if strings.TrimSpace(token) == "" {
			return usageError("token is required; pass --token or set ARGOCD_AUTH_TOKEN")
		}
	}

	evaluator, err := dependencies.newEvaluator(policyPath)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	var driftReport drift.DriftReport
	if fixturePath != "" {
		app, resources, loadErr := loadFixture(fixturePath)
		if loadErr != nil {
			return loadErr
		}
		driftReport, err = evaluateState(ctx, app, resources, evaluator, dependencies.now().UTC())
	} else {
		driftReport, err = scanArgoCD(ctx, appName, serverURL, token, evaluator, dependencies)
	}
	if err != nil {
		return err
	}

	switch output {
	case "json":
		return report.WriteJSON(stdout, driftReport)
	default:
		return report.WriteTerminal(stdout, driftReport)
	}
}

func scanArgoCD(ctx context.Context, appName, serverURL, token string, evaluator findingEvaluator, dependencies scanDependencies) (drift.DriftReport, error) {
	client, err := dependencies.newArgoClient(serverURL, token)
	if err != nil {
		return drift.DriftReport{}, err
	}
	app, err := client.GetApplication(ctx, appName)
	if err != nil {
		return drift.DriftReport{}, err
	}
	resources, err := client.GetManagedResources(ctx, appName)
	if err != nil {
		return drift.DriftReport{}, err
	}
	return evaluateState(ctx, app, resources, evaluator, dependencies.now().UTC())
}

func evaluateState(ctx context.Context, app *argocd.Application, resources *argocd.ManagedResourcesResponse, evaluator findingEvaluator, observedAt time.Time) (drift.DriftReport, error) {
	var driftReport drift.DriftReport
	if resources == nil {
		driftReport = drift.FromArgoCDApplication(app)
	} else {
		driftReport = drift.FromArgoCDManagedResources(app, resources, observedAt)
		if len(driftReport.Findings) == 0 && app != nil && strings.EqualFold(app.Status.Sync.Status, "OutOfSync") {
			driftReport = drift.FromArgoCDApplication(app)
		}
	}

	for index, finding := range driftReport.Findings {
		decisions, err := evaluator.EvaluateFinding(ctx, finding)
		if err != nil {
			return drift.DriftReport{}, fmt.Errorf("evaluate finding %q: %w", finding.ID, err)
		}
		driftReport.Findings[index] = policy.ApplyDecisions(finding, decisions)
	}
	return driftReport, nil
}

func loadFixture(path string) (*argocd.Application, *argocd.ManagedResourcesResponse, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, nil, fmt.Errorf("read fixture: %w", err)
	}

	var bundle scanFixture
	if err := json.Unmarshal(data, &bundle); err != nil {
		return nil, nil, fmt.Errorf("decode fixture as argocd application or scan bundle: %w", err)
	}
	if bundle.Application != nil || bundle.ManagedResources != nil {
		if bundle.Application == nil || bundle.ManagedResources == nil {
			return nil, nil, errors.New("decode scan bundle: application and managedResources are both required")
		}
		if strings.TrimSpace(bundle.Application.Metadata.Name) == "" {
			return nil, nil, errors.New("decode scan bundle: application.metadata.name is required")
		}
		return bundle.Application, bundle.ManagedResources, nil
	}

	var app argocd.Application
	if err := json.Unmarshal(data, &app); err != nil {
		return nil, nil, fmt.Errorf("decode fixture as argocd application or scan bundle: %w", err)
	}
	if strings.TrimSpace(app.Metadata.Name) == "" {
		return nil, nil, errors.New("decode argocd application fixture: metadata.name is required")
	}
	return &app, nil, nil
}

func firstConfigured(flagValue, environmentName, defaultValue string) string {
	if strings.TrimSpace(flagValue) != "" {
		return flagValue
	}
	if value := strings.TrimSpace(os.Getenv(environmentName)); value != "" {
		return value
	}
	return defaultValue
}

func usageError(message string) error {
	return errors.New(message + "\n\nUsage:\n  radar version\n  radar scan --app <argo-app-name> --server <argocd-server-url> --token <argocd-auth-token> --policy <rego-path> --output table\n  radar scan --fixture <sanitized-fixture> --policy <rego-path> --output json")
}
