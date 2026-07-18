package drift

import (
	"testing"
	"time"

	"github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift/internal/argocd"
)

var fixedObservation = time.Date(2026, 7, 19, 12, 0, 0, 0, time.UTC)

func TestFromArgoCDManagedResourcesExtractsReplaceAndIgnoresNoise(t *testing.T) {
	app := testApplication()
	resources := &argocd.ManagedResourcesResponse{Items: []argocd.ResourceDiff{{
		Group: "apps", Kind: "Deployment", Namespace: "demo", Name: "guestbook", Modified: true,
		PredictedLiveState:  `{"apiVersion":"apps/v1","kind":"Deployment","metadata":{"name":"guestbook","namespace":"demo","resourceVersion":"1"},"spec":{"template":{"spec":{"containers":[{"name":"app","securityContext":{"privileged":false}}]}}}}`,
		NormalizedLiveState: `{"apiVersion":"apps/v1","kind":"Deployment","metadata":{"name":"guestbook","namespace":"demo","resourceVersion":"2","managedFields":[{}]},"spec":{"template":{"spec":{"containers":[{"name":"app","securityContext":{"privileged":true}}]}}},"status":{"readyReplicas":1}}`,
	}}}

	report := FromArgoCDManagedResources(app, resources, fixedObservation)
	if len(report.Findings) != 1 {
		t.Fatalf("findings = %#v, want one security-context change", report.Findings)
	}
	finding := report.Findings[0]
	if finding.Change.Operation != "replace" || finding.Change.Path != "/spec/template/spec/containers/0/securityContext/privileged" {
		t.Fatalf("change = %#v", finding.Change)
	}
	if finding.Change.Before != false || finding.Change.After != true {
		t.Fatalf("before/after = %#v/%#v", finding.Change.Before, finding.Change.After)
	}
	if finding.Resource.Version != "v1" || finding.Resource.Group != "apps" {
		t.Fatalf("resource = %#v", finding.Resource)
	}
	if finding.ID == "" || finding.ObservedAt != fixedObservation {
		t.Fatalf("id/observedAt = %q/%s", finding.ID, finding.ObservedAt)
	}
}

func TestFromArgoCDManagedResourcesExtractsRootAddAndRemove(t *testing.T) {
	app := testApplication()
	resources := &argocd.ManagedResourcesResponse{Items: []argocd.ResourceDiff{
		{Kind: "ConfigMap", Namespace: "demo", Name: "unexpected", LiveState: `{"apiVersion":"v1","kind":"ConfigMap","metadata":{"name":"unexpected"}}`, Modified: true},
		{Kind: "NetworkPolicy", Namespace: "demo", Name: "default-deny", Group: "networking.k8s.io", TargetState: `{"apiVersion":"networking.k8s.io/v1","kind":"NetworkPolicy","metadata":{"name":"default-deny"}}`, Modified: true},
	}}
	report := FromArgoCDManagedResources(app, resources, fixedObservation)
	if len(report.Findings) != 2 {
		t.Fatalf("findings = %#v", report.Findings)
	}
	operations := map[string]string{}
	for _, finding := range report.Findings {
		operations[finding.Resource.Name] = finding.Change.Operation
	}
	if operations["unexpected"] != "add" || operations["default-deny"] != "remove" {
		t.Fatalf("operations = %#v", operations)
	}
}

func TestFromArgoCDManagedResourcesFallsBackAndIsDeterministic(t *testing.T) {
	app := testApplication()
	resources := &argocd.ManagedResourcesResponse{Items: []argocd.ResourceDiff{{
		Kind: "Service", Namespace: "demo", Name: "guestbook", Modified: true,
		PredictedLiveState: `{invalid`, NormalizedLiveState: `{"apiVersion":"v1","kind":"Service"}`,
	}}}
	first := FromArgoCDManagedResources(app, resources, fixedObservation)
	second := FromArgoCDManagedResources(app, resources, fixedObservation)
	if len(first.Findings) != 1 || first.Findings[0].Severity != "INFO" || first.Findings[0].Change.Confidence != "resource-status-only" {
		t.Fatalf("finding = %#v", first.Findings)
	}
	if first.Findings[0].ID != second.Findings[0].ID {
		t.Fatalf("ids differ: %q != %q", first.Findings[0].ID, second.Findings[0].ID)
	}
}

func TestFromArgoCDManagedResourcesSkipsUnmodifiedEqualResource(t *testing.T) {
	state := `{"apiVersion":"v1","kind":"ConfigMap","metadata":{"name":"settings"},"data":{"mode":"safe"}}`
	report := FromArgoCDManagedResources(testApplication(), &argocd.ManagedResourcesResponse{Items: []argocd.ResourceDiff{{
		Kind: "ConfigMap", Namespace: "demo", Name: "settings", TargetState: state, LiveState: state,
	}}}, fixedObservation)
	if len(report.Findings) != 0 {
		t.Fatalf("findings = %#v, want none", report.Findings)
	}
}

func testApplication() *argocd.Application {
	return &argocd.Application{
		Metadata: argocd.ApplicationMetadata{Name: "guestbook", Namespace: "argocd"},
		Spec:     argocd.ApplicationSpec{Project: "default"},
		Status: argocd.ApplicationStatus{
			Sync:   argocd.SyncStatus{Status: "OutOfSync"},
			Health: argocd.HealthStatus{Status: "Healthy"},
		},
	}
}
