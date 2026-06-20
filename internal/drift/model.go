package drift

import (
	"fmt"
	"strings"

	"github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift/internal/argocd"
)

type DriftReport struct {
	Application  string    `json:"application"`
	Project      string    `json:"project"`
	SyncStatus   string    `json:"syncStatus"`
	HealthStatus string    `json:"healthStatus"`
	Findings     []Finding `json:"findings"`
}

type Finding struct {
	ID             string      `json:"id"`
	Resource       ResourceRef `json:"resource"`
	Change         Change      `json:"change"`
	Severity       string      `json:"severity"`
	Score          int         `json:"score"`
	Reason         string      `json:"reason"`
	Recommendation string      `json:"recommendation"`
	EvidenceSource string      `json:"evidenceSource"`
}

type ResourceRef struct {
	Group     string `json:"group"`
	Version   string `json:"version"`
	Kind      string `json:"kind"`
	Namespace string `json:"namespace"`
	Name      string `json:"name"`
}

type Change struct {
	Operation  string `json:"operation"`
	Path       string `json:"path"`
	Before     any    `json:"before"`
	After      any    `json:"after"`
	Confidence string `json:"confidence"`
}

func FromArgoCDApplication(app *argocd.Application) DriftReport {
	if app == nil {
		return DriftReport{}
	}

	report := DriftReport{
		Application:  app.Metadata.Name,
		Project:      app.Spec.Project,
		SyncStatus:   app.Status.Sync.Status,
		HealthStatus: app.Status.Health.Status,
		Findings:     []Finding{},
	}

	for i, resource := range app.Status.Resources {
		if !strings.EqualFold(resource.Status, "OutOfSync") {
			continue
		}
		report.Findings = append(report.Findings, Finding{
			ID: fmt.Sprintf("RADAR-ARGOCD-%03d", i+1),
			Resource: ResourceRef{
				Group:     resource.Group,
				Version:   resource.Version,
				Kind:      resource.Kind,
				Namespace: resource.Namespace,
				Name:      resource.Name,
			},
			Change: Change{
				Operation:  "unknown",
				Path:       "unknown",
				Confidence: "resource-status-only",
			},
			Severity:       "INFO",
			Score:          0,
			Reason:         "Argo CD reports this resource as OutOfSync, but field-level diff data is unavailable.",
			Recommendation: "Fetch field-level diff data before assigning a security severity.",
			EvidenceSource: "argocd-application-status",
		})
	}

	return report
}

func (r ResourceRef) String() string {
	parts := []string{}
	if r.Group != "" {
		parts = append(parts, r.Group)
	}
	if r.Version != "" {
		parts = append(parts, r.Version)
	}
	if r.Kind != "" {
		parts = append(parts, r.Kind)
	}
	if r.Namespace != "" {
		parts = append(parts, r.Namespace)
	}
	if r.Name != "" {
		parts = append(parts, r.Name)
	}
	return strings.Join(parts, "/")
}
