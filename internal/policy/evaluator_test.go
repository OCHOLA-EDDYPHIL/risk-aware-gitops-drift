package policy

import (
	"context"
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift/internal/drift"
)

func TestEvaluatorRequiresOPAPath(t *testing.T) {
	evaluator := NewEvaluatorWithOPAPath("", "policies/risk.rego")
	_, err := evaluator.EvaluateFinding(context.Background(), drift.Finding{})
	if err == nil {
		t.Fatal("EvaluateFinding() error = nil, want missing OPA path error")
	}
}

func TestEvaluatorDecodesEvidenceRichDecision(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("test helper uses a POSIX shell script")
	}
	dir := t.TempDir()
	opaPath := filepath.Join(dir, "opa")
	script := `#!/bin/sh
cat >/dev/null
printf '%s' '{"result":[{"expressions":[{"value":[{"ruleId":"RADAR-RBAC-WILDCARD","impact":5,"likelihood":5,"severity":"CRITICAL","score":100,"reason":"Privilege expansion.","recommendation":"Revert it."}]}]}]}'
`
	if err := os.WriteFile(opaPath, []byte(script), 0o700); err != nil {
		t.Fatalf("write fake opa: %v", err)
	}

	evaluator := NewEvaluatorWithOPAPath(opaPath, "policies/risk.rego")
	decisions, err := evaluator.EvaluateFinding(context.Background(), drift.Finding{ID: "fixture"})
	if err != nil {
		t.Fatalf("EvaluateFinding() error = %v", err)
	}
	if len(decisions) != 1 {
		t.Fatalf("decisions = %#v", decisions)
	}
	decision := decisions[0]
	if decision.RuleID != "RADAR-RBAC-WILDCARD" || decision.Impact != 5 || decision.Likelihood != 5 || decision.Score != 100 {
		t.Fatalf("decision = %#v", decision)
	}
}
