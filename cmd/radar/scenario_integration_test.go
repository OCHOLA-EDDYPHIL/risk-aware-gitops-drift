package main

import (
	"bytes"
	"encoding/json"
	"os/exec"
	"path/filepath"
	"reflect"
	"testing"
	"time"

	"github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift/internal/drift"
)

func TestRunScanScenarioBundlesWithRealOPA(t *testing.T) {
	if _, err := exec.LookPath("opa"); err != nil {
		t.Skip("OPA is unavailable")
	}

	tests := []struct {
		name     string
		fixture  string
		ruleID   string
		severity string
		path     string
		before   any
		after    any
	}{
		{name: "rbac wildcard", fixture: "scan_bundle_rbac_wildcard.json", ruleID: "RADAR-RBAC-WILDCARD", severity: "CRITICAL", path: "/rules", before: nil, after: []any{map[string]any{"apiGroups": []any{"*"}, "resources": []any{"*"}, "verbs": []any{"*"}}}},
		{name: "network policy removal", fixture: "scan_bundle_networkpolicy_removal.json", ruleID: "RADAR-NETPOL-REMOVED", severity: "HIGH", path: "", before: map[string]any{"apiVersion": "networking.k8s.io/v1", "kind": "NetworkPolicy", "metadata": map[string]any{"name": "radar-demo-default-deny-ingress", "namespace": "radar-demo"}, "spec": map[string]any{"podSelector": map[string]any{}, "policyTypes": []any{"Ingress"}}}, after: nil},
		{name: "host path addition", fixture: "scan_bundle_hostpath_addition.json", ruleID: "RADAR-VOLUME-HOSTPATH", severity: "HIGH", path: "/spec/template/spec/volumes/0/hostPath", before: nil, after: map[string]any{"path": "/var/log", "type": "Directory"}},
		{name: "service exposure", fixture: "scan_bundle_service_exposure.json", ruleID: "RADAR-SERVICE-EXPOSURE", severity: "HIGH", path: "/spec/type", before: "ClusterIP", after: "NodePort"},
		{name: "unsafe image tag", fixture: "scan_bundle_unsafe_image_tag.json", ruleID: "RADAR-IMAGE-LATEST", severity: "MEDIUM", path: "/spec/template/spec/containers/0/image", before: "nginx:1.27.5", after: "nginx:latest"},
		{name: "secret reference", fixture: "scan_bundle_secret_reference.json", ruleID: "RADAR-SECRET-REFERENCE", severity: "MEDIUM", path: "/spec/template/spec/containers/0/env/0/valueFrom/secretKeyRef/name", before: "radar-demo-credentials-v1", after: "radar-demo-credentials-v2"},
		{name: "metadata control", fixture: "scan_bundle_metadata_only.json", ruleID: "RADAR-METADATA-ONLY", severity: "LOW", path: "/metadata/labels", before: nil, after: map[string]any{"radar.research/scenario": "metadata-only"}},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			dependencies := productionDependencies
			dependencies.now = func() time.Time { return fixedScanTime }
			args := []string{
				"scan",
				"--fixture", filepath.Join("..", "..", "testdata", "argocd", test.fixture),
				"--policy", filepath.Join("..", "..", "policies", "risk.rego"),
				"--output", "json",
			}

			var first bytes.Buffer
			if err := run(args, &first, &bytes.Buffer{}, dependencies); err != nil {
				t.Fatalf("first run: %v", err)
			}
			var second bytes.Buffer
			if err := run(args, &second, &bytes.Buffer{}, dependencies); err != nil {
				t.Fatalf("second run: %v", err)
			}
			if first.String() != second.String() {
				t.Fatal("fixed input and time produced different JSON reports")
			}

			var report drift.DriftReport
			if err := json.Unmarshal(first.Bytes(), &report); err != nil {
				t.Fatalf("decode report: %v", err)
			}
			if report.SyncStatus != "OutOfSync" || len(report.Findings) == 0 {
				t.Fatalf("report did not preserve observable drift: %#v", report)
			}

			for _, finding := range report.Findings {
				if finding.RuleID != test.ruleID {
					continue
				}
				if finding.Severity != test.severity || finding.Change.Path != test.path {
					t.Fatalf("classified finding = %#v", finding)
				}
				if !reflect.DeepEqual(finding.Change.Before, test.before) || !reflect.DeepEqual(finding.Change.After, test.after) {
					t.Fatalf("before/after = %#v/%#v", finding.Change.Before, finding.Change.After)
				}
				if finding.EvidenceSource != "argocd-managed-resources" || finding.Change.Confidence != "field-level" {
					t.Fatalf("evidence = %#v", finding)
				}
				return
			}
			t.Fatalf("expected %s finding in %#v", test.ruleID, report.Findings)
		})
	}
}
