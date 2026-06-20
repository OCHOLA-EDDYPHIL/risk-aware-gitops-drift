package policy

import (
	"context"
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
