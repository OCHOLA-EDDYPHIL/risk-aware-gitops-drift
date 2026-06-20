package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"strings"

	"github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift/internal/argocd"
	"github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift/internal/drift"
	"github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift/internal/report"
	"github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift/internal/version"
)

func main() {
	if err := run(os.Args[1:], os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run(args []string, stdout *os.File) error {
	if len(args) == 0 {
		return usageError("command is required")
	}

	switch args[0] {
	case "version":
		_, err := fmt.Fprintf(stdout, "%s %s (%s, %s)\n", version.Name, version.Version, version.Commit, version.Date)
		return err
	case "scan":
		return runScan(args[1:], stdout)
	default:
		return usageError("unknown command " + args[0])
	}
}

func runScan(args []string, stdout *os.File) error {
	flags := flag.NewFlagSet("scan", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)

	var appName string
	var serverURL string
	var token string
	var output string
	var fixturePath string

	flags.StringVar(&appName, "app", "", "Argo CD application name")
	flags.StringVar(&serverURL, "server", "", "Argo CD server URL")
	flags.StringVar(&token, "token", "", "Argo CD auth token")
	flags.StringVar(&output, "output", "", "Output format: table or json")
	flags.StringVar(&fixturePath, "fixture", "", "Read a sanitized Argo CD Application fixture instead of calling the API")

	if err := flags.Parse(args); err != nil {
		return err
	}

	if appName == "" {
		appName = flags.Lookup("app").Value.String()
	}
	if serverURL == "" {
		serverURL = os.Getenv("ARGOCD_SERVER")
	}
	if token == "" {
		token = os.Getenv("ARGOCD_AUTH_TOKEN")
	}
	if output == "" {
		output = os.Getenv("RADAR_OUTPUT")
	}
	if output == "" {
		output = "table"
	}

	output = strings.ToLower(output)
	if output != "table" && output != "json" {
		return usageError("output must be table or json")
	}

	var driftReport drift.DriftReport
	var err error
	if fixturePath != "" {
		driftReport, err = loadFixture(fixturePath)
	} else {
		driftReport, err = scanArgoCD(context.Background(), appName, serverURL, token)
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

func scanArgoCD(ctx context.Context, appName string, serverURL string, token string) (drift.DriftReport, error) {
	if strings.TrimSpace(appName) == "" {
		return drift.DriftReport{}, usageError("app is required")
	}
	if strings.TrimSpace(serverURL) == "" {
		return drift.DriftReport{}, usageError("server is required; pass --server or set ARGOCD_SERVER")
	}
	if strings.TrimSpace(token) == "" {
		return drift.DriftReport{}, usageError("token is required; pass --token or set ARGOCD_AUTH_TOKEN")
	}

	client, err := argocd.NewClient(serverURL, token)
	if err != nil {
		return drift.DriftReport{}, err
	}
	app, err := client.GetApplication(ctx, appName)
	if err != nil {
		return drift.DriftReport{}, err
	}
	return drift.FromArgoCDApplication(app), nil
}

func loadFixture(path string) (drift.DriftReport, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return drift.DriftReport{}, fmt.Errorf("read fixture: %w", err)
	}

	var app argocd.Application
	if err := json.Unmarshal(data, &app); err != nil {
		return drift.DriftReport{}, fmt.Errorf("decode fixture as argocd application: %w", err)
	}
	return drift.FromArgoCDApplication(&app), nil
}

func usageError(message string) error {
	return errors.New(message + "\n\nUsage:\n  radar version\n  radar scan --app <argo-app-name> --server <argocd-server-url> --token <argocd-auth-token> --output table\n  radar scan --app <argo-app-name> --server <argocd-server-url> --token <argocd-auth-token> --output json")
}
