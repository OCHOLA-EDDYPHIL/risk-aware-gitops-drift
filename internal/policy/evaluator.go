package policy

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"

	"github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift/internal/drift"
)

type Decision struct {
	Severity       string `json:"severity"`
	Score          int    `json:"score"`
	Reason         string `json:"reason"`
	Recommendation string `json:"recommendation"`
}

type Evaluator struct {
	opaPath    string
	policyPath string
}

func NewEvaluator(policyPath string) (*Evaluator, error) {
	opaPath, err := exec.LookPath("opa")
	if err != nil {
		return nil, errors.New("opa CLI is required for policy evaluation but was not found in PATH")
	}
	return &Evaluator{opaPath: opaPath, policyPath: policyPath}, nil
}

func NewEvaluatorWithOPAPath(opaPath string, policyPath string) *Evaluator {
	return &Evaluator{opaPath: opaPath, policyPath: policyPath}
}

func (e *Evaluator) EvaluateFinding(ctx context.Context, finding drift.Finding) ([]Decision, error) {
	if e == nil || e.opaPath == "" {
		return nil, errors.New("opa CLI path is required")
	}
	if e.policyPath == "" {
		return nil, errors.New("rego policy path is required")
	}

	input, err := json.Marshal(finding)
	if err != nil {
		return nil, fmt.Errorf("marshal policy input: %w", err)
	}

	cmd := exec.CommandContext(ctx, e.opaPath, "eval", "--stdin-input", "--data", e.policyPath, "--format", "json", "data.radar.risk.findings")
	cmd.Stdin = bytes.NewReader(input)

	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("run opa policy evaluation: %w: %s", err, stderr.String())
	}

	var result opaEvalResult
	if err := json.Unmarshal(stdout.Bytes(), &result); err != nil {
		return nil, fmt.Errorf("decode opa policy result: %w", err)
	}
	if len(result.Result) == 0 || len(result.Result[0].Expressions) == 0 {
		return []Decision{}, nil
	}

	raw, err := json.Marshal(result.Result[0].Expressions[0].Value)
	if err != nil {
		return nil, fmt.Errorf("marshal opa decision value: %w", err)
	}

	var decisions []Decision
	if err := json.Unmarshal(raw, &decisions); err != nil {
		return nil, fmt.Errorf("decode opa decisions: %w", err)
	}
	return decisions, nil
}

type opaEvalResult struct {
	Result []struct {
		Expressions []struct {
			Value any `json:"value"`
		} `json:"expressions"`
	} `json:"result"`
}
