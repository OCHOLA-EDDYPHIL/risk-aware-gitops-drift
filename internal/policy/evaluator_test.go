package policy

import (
	"context"
	"os"
	"path/filepath"
	"runtime"
	"strings"
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

func TestEvaluatorRejectsMalformedOPAOutput(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("test helper uses a POSIX shell script")
	}
	dir := t.TempDir()
	opaPath := filepath.Join(dir, "opa")
	script := `#!/bin/sh
cat >/dev/null
printf '%s' 'not-json'
`
	if err := os.WriteFile(opaPath, []byte(script), 0o700); err != nil {
		t.Fatalf("write fake opa: %v", err)
	}

	evaluator := NewEvaluatorWithOPAPath(opaPath, "policies/risk.rego")
	_, err := evaluator.EvaluateFinding(context.Background(), drift.Finding{ID: "fixture"})
	if err == nil || !strings.Contains(err.Error(), "decode opa policy result") {
		t.Fatalf("EvaluateFinding() error = %v", err)
	}
}

func TestApplyDecisionsSelectsHighestScoreAndRetainsSortedRuleIDs(t *testing.T) {
	finding := drift.Finding{ID: "fixture", Change: drift.Change{Confidence: "field-level"}}
	decisions := []Decision{
		{RuleID: "RADAR-SECRET-REFERENCE", Impact: 4, Likelihood: 2, Severity: "MEDIUM", Score: 32, Reason: "secret", Recommendation: "review"},
		{RuleID: "RADAR-VOLUME-HOSTPATH", Impact: 5, Likelihood: 3, Severity: "HIGH", Score: 60, Reason: "host path", Recommendation: "remove"},
	}
	result := ApplyDecisions(finding, decisions)
	if result.RuleID != "RADAR-VOLUME-HOSTPATH" || result.Score != 60 || result.Severity != "HIGH" {
		t.Fatalf("result = %#v", result)
	}
	if len(result.MatchedRuleIDs) != 2 || result.MatchedRuleIDs[0] != "RADAR-SECRET-REFERENCE" || result.MatchedRuleIDs[1] != "RADAR-VOLUME-HOSTPATH" {
		t.Fatalf("matched rules = %#v", result.MatchedRuleIDs)
	}
}

func TestApplyDecisionsBreaksScoreTieByRuleID(t *testing.T) {
	result := ApplyDecisions(drift.Finding{}, []Decision{
		{RuleID: "RADAR-Z", Severity: "HIGH", Score: 64},
		{RuleID: "RADAR-A", Severity: "HIGH", Score: 64},
	})
	if result.RuleID != "RADAR-A" {
		t.Fatalf("selected rule = %q, want RADAR-A", result.RuleID)
	}
}

func TestApplyDecisionsPreservesInfoForNoMatch(t *testing.T) {
	finding := drift.Finding{Severity: "INFO", Change: drift.Change{Confidence: "field-level"}}
	result := ApplyDecisions(finding, nil)
	if result.Severity != "INFO" || result.Score != 0 || result.Reason == "" {
		t.Fatalf("result = %#v", result)
	}
}
