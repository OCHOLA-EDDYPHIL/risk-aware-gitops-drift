package report

import (
	"fmt"
	"io"

	"github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift/internal/drift"
)

func WriteTerminal(w io.Writer, report drift.DriftReport) error {
	if _, err := fmt.Fprintln(w, "RADAR Drift Report"); err != nil {
		return err
	}
	lines := []string{
		fmt.Sprintf("Application: %s", report.Application),
		fmt.Sprintf("Project: %s", report.Project),
		fmt.Sprintf("Sync Status: %s", report.SyncStatus),
		fmt.Sprintf("Health Status: %s", report.HealthStatus),
		"",
		"Findings:",
		"",
		"| Severity | Score | Rule | Resource | Change | Reason | Recommendation |",
		"| -------- | ----- | ---- | -------- | ------ | ------ | -------------- |",
	}
	for _, line := range lines {
		if _, err := fmt.Fprintln(w, line); err != nil {
			return err
		}
	}

	for _, finding := range report.Findings {
		change := finding.Change.Operation + " " + finding.Change.Path
		if _, err := fmt.Fprintf(
			w,
			"| %s | %d | %s | %s | %s | %s | %s |\n",
			finding.Severity,
			finding.Score,
			finding.RuleID,
			finding.Resource.String(),
			change,
			finding.Reason,
			finding.Recommendation,
		); err != nil {
			return err
		}
	}

	if len(report.Findings) == 0 {
		_, err := fmt.Fprintln(w, "No findings.")
		return err
	}

	return nil
}
