package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift/internal/argocd"
	"github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift/internal/drift"
	"github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift/internal/policy"
)

var fixedScanTime = time.Date(2026, 7, 19, 14, 30, 0, 0, time.FixedZone("EAT", 3*60*60))

type fakeArgoAPI struct {
	application      *argocd.Application
	resources        *argocd.ManagedResourcesResponse
	applicationErr   error
	resourcesErr     error
	applicationCalls []string
	resourceCalls    []string
}

func (f *fakeArgoAPI) GetApplication(_ context.Context, appName string) (*argocd.Application, error) {
	f.applicationCalls = append(f.applicationCalls, appName)
	return f.application, f.applicationErr
}

func (f *fakeArgoAPI) GetManagedResources(_ context.Context, appName string) (*argocd.ManagedResourcesResponse, error) {
	f.resourceCalls = append(f.resourceCalls, appName)
	return f.resources, f.resourcesErr
}

type evaluatorFunc func(context.Context, drift.Finding) ([]policy.Decision, error)

func (f evaluatorFunc) EvaluateFinding(ctx context.Context, finding drift.Finding) ([]policy.Decision, error) {
	return f(ctx, finding)
}

func TestRunScanCompletesManagedResourcePolicyReportPath(t *testing.T) {
	api := &fakeArgoAPI{
		application: testApplication("OutOfSync"),
		resources:   privilegedResources(),
	}
	evaluationCalls := 0
	dependencies := scanDependencies{
		newArgoClient: func(serverURL, token string) (argoAPI, error) {
			if serverURL != "https://argocd.test" || token != "test-token" {
				t.Fatalf("client configuration = %q/%q", serverURL, token)
			}
			return api, nil
		},
		newEvaluator: func(policyPath string) (findingEvaluator, error) {
			if policyPath != "test-policy.rego" {
				t.Fatalf("policy path = %q", policyPath)
			}
			return evaluatorFunc(func(_ context.Context, finding drift.Finding) ([]policy.Decision, error) {
				evaluationCalls++
				if finding.Change.Path != "/spec/template/spec/containers/0/securityContext/privileged" || finding.Change.After != true {
					t.Fatalf("policy input = %#v", finding)
				}
				return []policy.Decision{{
					RuleID: "RADAR-WORKLOAD-PRIVILEGED", Impact: 5, Likelihood: 5,
					Severity: "CRITICAL", Score: 100, Reason: "Privileged mode enabled.", Recommendation: "Disable privileged mode.",
				}}, nil
			}), nil
		},
		now: func() time.Time { return fixedScanTime },
	}

	var stdout, stderr bytes.Buffer
	err := run([]string{
		"scan", "--app", "guestbook", "--server", "https://argocd.test", "--token", "test-token",
		"--policy", "test-policy.rego", "--output", "json",
	}, &stdout, &stderr, dependencies)
	if err != nil {
		t.Fatalf("run() error = %v; stderr = %s", err, stderr.String())
	}

	var got drift.DriftReport
	if err := json.Unmarshal(stdout.Bytes(), &got); err != nil {
		t.Fatalf("decode report: %v\n%s", err, stdout.String())
	}
	if evaluationCalls != 1 || len(api.applicationCalls) != 1 || len(api.resourceCalls) != 1 {
		t.Fatalf("calls: evaluator=%d application=%v resources=%v", evaluationCalls, api.applicationCalls, api.resourceCalls)
	}
	if len(got.Findings) != 1 {
		t.Fatalf("findings = %#v", got.Findings)
	}
	finding := got.Findings[0]
	if finding.RuleID != "RADAR-WORKLOAD-PRIVILEGED" || finding.Severity != "CRITICAL" || finding.Score != 100 {
		t.Fatalf("classified finding = %#v", finding)
	}
	if !finding.ObservedAt.Equal(fixedScanTime.UTC()) {
		t.Fatalf("observedAt = %s, want %s", finding.ObservedAt, fixedScanTime.UTC())
	}
}

func TestRunScanFlagsOverrideEnvironment(t *testing.T) {
	t.Setenv("ARGOCD_SERVER", "https://environment.test")
	t.Setenv("ARGOCD_AUTH_TOKEN", "environment-token")
	t.Setenv("RADAR_POLICY_PATH", "environment.rego")
	t.Setenv("RADAR_OUTPUT", "json")

	api := &fakeArgoAPI{application: testApplication("Synced"), resources: &argocd.ManagedResourcesResponse{Items: []argocd.ResourceDiff{}}}
	var gotServer, gotToken, gotPolicy string
	dependencies := scanDependencies{
		newArgoClient: func(serverURL, token string) (argoAPI, error) {
			gotServer, gotToken = serverURL, token
			return api, nil
		},
		newEvaluator: func(policyPath string) (findingEvaluator, error) {
			gotPolicy = policyPath
			return evaluatorFunc(func(context.Context, drift.Finding) ([]policy.Decision, error) { return nil, nil }), nil
		},
		now: time.Now,
	}

	var stdout bytes.Buffer
	err := run([]string{
		"scan", "--app", "guestbook", "--server", "https://flag.test", "--token", "flag-token",
		"--policy", "flag.rego", "--output", "table",
	}, &stdout, &bytes.Buffer{}, dependencies)
	if err != nil {
		t.Fatalf("run() error = %v", err)
	}
	if gotServer != "https://flag.test" || gotToken != "flag-token" || gotPolicy != "flag.rego" {
		t.Fatalf("resolved configuration = %q/%q/%q", gotServer, gotToken, gotPolicy)
	}
	if !strings.HasPrefix(stdout.String(), "RADAR Drift Report") {
		t.Fatalf("flag output did not override JSON environment setting:\n%s", stdout.String())
	}
}

func TestRunScanLoadsScanBundleFixture(t *testing.T) {
	dependencies := scanDependencies{
		newArgoClient: func(string, string) (argoAPI, error) {
			t.Fatal("fixture scan must not create an Argo CD client")
			return nil, nil
		},
		newEvaluator: func(string) (findingEvaluator, error) {
			return evaluatorFunc(func(_ context.Context, finding drift.Finding) ([]policy.Decision, error) {
				if finding.EvidenceSource != "argocd-managed-resources" {
					t.Fatalf("evidence source = %q", finding.EvidenceSource)
				}
				return []policy.Decision{{RuleID: "RADAR-WORKLOAD-PRIVILEGED", Severity: "CRITICAL", Score: 100}}, nil
			}), nil
		},
		now: func() time.Time { return fixedScanTime },
	}

	var stdout bytes.Buffer
	err := run([]string{"scan", "--fixture", fixturePath("scan_bundle_privileged.json"), "--output", "json"}, &stdout, &bytes.Buffer{}, dependencies)
	if err != nil {
		t.Fatalf("run() error = %v", err)
	}
	var got drift.DriftReport
	if err := json.Unmarshal(stdout.Bytes(), &got); err != nil {
		t.Fatalf("decode report: %v", err)
	}
	if len(got.Findings) != 1 || got.Findings[0].RuleID != "RADAR-WORKLOAD-PRIVILEGED" {
		t.Fatalf("report = %#v", got)
	}
}

func TestRunScanLegacyApplicationFixtureRemainsInformationOnly(t *testing.T) {
	dependencies := scanDependencies{
		newArgoClient: func(string, string) (argoAPI, error) { return nil, errors.New("unexpected client creation") },
		newEvaluator: func(string) (findingEvaluator, error) {
			return evaluatorFunc(func(_ context.Context, finding drift.Finding) ([]policy.Decision, error) {
				if finding.Change.Confidence != "resource-status-only" {
					t.Fatalf("confidence = %q", finding.Change.Confidence)
				}
				return []policy.Decision{{
					RuleID: "RADAR-INSUFFICIENT-EVIDENCE", Severity: "INFO", Score: 0,
					Reason: "Field-level evidence is unavailable.", Recommendation: "Collect field-level evidence.",
				}}, nil
			}), nil
		},
		now: func() time.Time { return fixedScanTime },
	}

	var stdout bytes.Buffer
	err := run([]string{"scan", "--fixture", fixturePath("application_outofsync.json"), "--output", "json"}, &stdout, &bytes.Buffer{}, dependencies)
	if err != nil {
		t.Fatalf("run() error = %v", err)
	}
	var got drift.DriftReport
	if err := json.Unmarshal(stdout.Bytes(), &got); err != nil {
		t.Fatalf("decode report: %v", err)
	}
	if len(got.Findings) != 1 || got.Findings[0].Severity != "INFO" || got.Findings[0].Score != 0 {
		t.Fatalf("report = %#v", got)
	}
}

func TestLoadFixtureRejectsMalformedEvidence(t *testing.T) {
	tests := map[string]string{
		"invalid JSON":        `{`,
		"empty object":        `{}`,
		"partial scan bundle": `{"application":{"metadata":{"name":"guestbook"}}}`,
	}
	for name, contents := range tests {
		t.Run(name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "fixture.json")
			if err := os.WriteFile(path, []byte(contents), 0o600); err != nil {
				t.Fatalf("write fixture: %v", err)
			}
			if _, _, err := loadFixture(path); err == nil {
				t.Fatal("loadFixture() error = nil")
			}
		})
	}
}

func TestRunScanPropagatesEvaluatorFailureAndTimeout(t *testing.T) {
	t.Run("failure", func(t *testing.T) {
		dependencies := fixtureDependencies(evaluatorFunc(func(context.Context, drift.Finding) ([]policy.Decision, error) {
			return nil, errors.New("policy engine failed")
		}))
		err := run([]string{"scan", "--fixture", fixturePath("scan_bundle_privileged.json")}, &bytes.Buffer{}, &bytes.Buffer{}, dependencies)
		if err == nil || !strings.Contains(err.Error(), "policy engine failed") {
			t.Fatalf("run() error = %v", err)
		}
	})

	t.Run("timeout", func(t *testing.T) {
		dependencies := fixtureDependencies(evaluatorFunc(func(ctx context.Context, _ drift.Finding) ([]policy.Decision, error) {
			<-ctx.Done()
			return nil, ctx.Err()
		}))
		err := run([]string{"scan", "--fixture", fixturePath("scan_bundle_privileged.json"), "--timeout", "1ms"}, &bytes.Buffer{}, &bytes.Buffer{}, dependencies)
		if !errors.Is(err, context.DeadlineExceeded) {
			t.Fatalf("run() error = %v, want deadline exceeded", err)
		}
	})
}

func TestRunScanDoesNotLeakTokenInErrorsOrOutput(t *testing.T) {
	const token = "radar-super-secret-token"
	api := &fakeArgoAPI{applicationErr: errors.New("argocd request was unauthorized")}
	dependencies := scanDependencies{
		newArgoClient: func(_ string, gotToken string) (argoAPI, error) {
			if gotToken != token {
				t.Fatalf("token was not passed to client")
			}
			return api, nil
		},
		newEvaluator: func(string) (findingEvaluator, error) {
			return evaluatorFunc(func(context.Context, drift.Finding) ([]policy.Decision, error) { return nil, nil }), nil
		},
		now: time.Now,
	}
	var stdout, stderr bytes.Buffer
	err := run([]string{"scan", "--app", "guestbook", "--server", "https://argocd.test", "--token", token}, &stdout, &stderr, dependencies)
	if err == nil {
		t.Fatal("run() error = nil")
	}
	combined := err.Error() + stdout.String() + stderr.String()
	if strings.Contains(combined, token) {
		t.Fatalf("token leaked in command result: %s", combined)
	}
}

func fixtureDependencies(evaluator findingEvaluator) scanDependencies {
	return scanDependencies{
		newArgoClient: func(string, string) (argoAPI, error) { return nil, errors.New("unexpected client creation") },
		newEvaluator:  func(string) (findingEvaluator, error) { return evaluator, nil },
		now:           func() time.Time { return fixedScanTime },
	}
}

func fixturePath(name string) string {
	return filepath.Join("..", "..", "testdata", "argocd", name)
}

func testApplication(syncStatus string) *argocd.Application {
	return &argocd.Application{
		Metadata: argocd.ApplicationMetadata{Name: "guestbook", Namespace: "argocd"},
		Spec:     argocd.ApplicationSpec{Project: "default"},
		Status: argocd.ApplicationStatus{
			Sync:   argocd.SyncStatus{Status: syncStatus},
			Health: argocd.HealthStatus{Status: "Healthy"},
		},
	}
}

func privilegedResources() *argocd.ManagedResourcesResponse {
	return &argocd.ManagedResourcesResponse{Items: []argocd.ResourceDiff{{
		Group: "apps", Kind: "Deployment", Namespace: "demo", Name: "guestbook", Modified: true,
		PredictedLiveState:  `{"apiVersion":"apps/v1","kind":"Deployment","metadata":{"name":"guestbook"},"spec":{"template":{"spec":{"containers":[{"name":"guestbook","securityContext":{"privileged":false}}]}}}}`,
		NormalizedLiveState: `{"apiVersion":"apps/v1","kind":"Deployment","metadata":{"name":"guestbook"},"spec":{"template":{"spec":{"containers":[{"name":"guestbook","securityContext":{"privileged":true}}]}}}}`,
	}}}
}
