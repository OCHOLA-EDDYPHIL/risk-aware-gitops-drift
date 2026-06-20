package report

import (
	"encoding/json"
	"io"

	"github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift/internal/drift"
)

func WriteJSON(w io.Writer, report drift.DriftReport) error {
	if report.Findings == nil {
		report.Findings = []drift.Finding{}
	}

	encoder := json.NewEncoder(w)
	encoder.SetIndent("", "  ")
	return encoder.Encode(report)
}
