package report

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"

	"github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift/internal/drift"
)

func testReport() drift.DriftReport {
	return drift.DriftReport{
		Application:  "guestbook",
		Project:      "default",
		SyncStatus:   "OutOfSync",
		HealthStatus: "Healthy",
		Findings: []drift.Finding{
			{
				ID:       "RADAR-001",
				Severity: "INFO",
				Score:    0,
				Resource: drift.ResourceRef{Group: "apps", Version: "v1", Kind: "Deployment", Namespace: "demo", Name: "guestbook"},
				Change: drift.Change{
					Operation:  "unknown",
					Path:       "unknown",
					Confidence: "resource-status-only",
				},
				Reason:         "Argo CD reports this resource as OutOfSync.",
				Recommendation: "Fetch field-level diff data.",
				EvidenceSource: "argocd-application-status",
			},
		},
	}
}

func TestWriteJSONIsValid(t *testing.T) {
	var buf bytes.Buffer
	if err := WriteJSON(&buf, testReport()); err != nil {
		t.Fatalf("WriteJSON() error = %v", err)
	}

	var decoded drift.DriftReport
	if err := json.Unmarshal(buf.Bytes(), &decoded); err != nil {
		t.Fatalf("json.Unmarshal() error = %v", err)
	}
	if decoded.Application != "guestbook" {
		t.Fatalf("application = %q", decoded.Application)
	}
}

func TestWriteTerminalContainsExpectedFields(t *testing.T) {
	var buf bytes.Buffer
	if err := WriteTerminal(&buf, testReport()); err != nil {
		t.Fatalf("WriteTerminal() error = %v", err)
	}

	output := buf.String()
	for _, want := range []string{"RADAR Drift Report", "Application: guestbook", "INFO", "Deployment"} {
		if !strings.Contains(output, want) {
			t.Fatalf("terminal output missing %q:\n%s", want, output)
		}
	}
}
