package drift

import (
	"testing"

	"github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift/internal/argocd"
)

func TestFromArgoCDApplicationCreatesResourceLevelFindings(t *testing.T) {
	app := &argocd.Application{
		Metadata: argocd.ApplicationMetadata{Name: "guestbook", Namespace: "argocd"},
		Spec:     argocd.ApplicationSpec{Project: "default"},
		Status: argocd.ApplicationStatus{
			Sync:   argocd.SyncStatus{Status: "OutOfSync"},
			Health: argocd.HealthStatus{Status: "Healthy"},
			Resources: []argocd.ResourceStatus{
				{Group: "apps", Version: "v1", Kind: "Deployment", Namespace: "demo", Name: "guestbook", Status: "OutOfSync"},
				{Group: "", Version: "v1", Kind: "Service", Namespace: "demo", Name: "guestbook", Status: "Synced"},
			},
		},
	}

	report := FromArgoCDApplication(app)

	if report.Application != "guestbook" {
		t.Fatalf("application = %q", report.Application)
	}
	if len(report.Findings) != 1 {
		t.Fatalf("findings length = %d, want 1", len(report.Findings))
	}

	finding := report.Findings[0]
	if finding.EvidenceSource != "argocd-application-status" {
		t.Fatalf("evidence source = %q", finding.EvidenceSource)
	}
	if finding.Change.Confidence != "resource-status-only" {
		t.Fatalf("confidence = %q", finding.Change.Confidence)
	}
	if finding.Change.Operation != "unknown" || finding.Change.Path != "unknown" {
		t.Fatalf("change = %#v, want unknown operation and path", finding.Change)
	}
	if finding.Severity != "INFO" || finding.Score != 0 {
		t.Fatalf("severity/score = %s/%d, want INFO/0", finding.Severity, finding.Score)
	}
}
