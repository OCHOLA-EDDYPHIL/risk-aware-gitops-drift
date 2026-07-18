package drift

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift/internal/argocd"
	"github.com/wI2L/jsondiff"
)

const managedResourcesEvidence = "argocd-managed-resources"

var ignoredMetadataFields = []string{
	"creationTimestamp",
	"deletionGracePeriodSeconds",
	"deletionTimestamp",
	"generation",
	"managedFields",
	"resourceVersion",
	"selfLink",
	"uid",
}

// FromArgoCDManagedResources converts Argo CD desired/live resource pairs into
// deterministic, atomic RADAR findings. The comparison direction is desired
// state to live state, so Change.After always represents the observed cluster.
func FromArgoCDManagedResources(app *argocd.Application, resources *argocd.ManagedResourcesResponse, observedAt time.Time) DriftReport {
	report := reportFromApplication(app)
	if resources == nil {
		return report
	}

	items := append([]argocd.ResourceDiff(nil), resources.Items...)
	sort.SliceStable(items, func(i, j int) bool {
		return resourceDiffKey(items[i]) < resourceDiffKey(items[j])
	})

	for _, item := range items {
		findings := findingsFromResourceDiff(item, observedAt.UTC())
		report.Findings = append(report.Findings, findings...)
	}
	sort.SliceStable(report.Findings, func(i, j int) bool {
		left := report.Findings[i]
		right := report.Findings[j]
		if left.Resource.String() != right.Resource.String() {
			return left.Resource.String() < right.Resource.String()
		}
		if left.Change.Path != right.Change.Path {
			return left.Change.Path < right.Change.Path
		}
		return left.Change.Operation < right.Change.Operation
	})
	return report
}

func reportFromApplication(app *argocd.Application) DriftReport {
	if app == nil {
		return DriftReport{Findings: []Finding{}}
	}
	return DriftReport{
		Application:  app.Metadata.Name,
		Project:      app.Spec.Project,
		SyncStatus:   app.Status.Sync.Status,
		HealthStatus: app.Status.Health.Status,
		Findings:     []Finding{},
	}
}

func findingsFromResourceDiff(item argocd.ResourceDiff, observedAt time.Time) []Finding {
	desiredRaw := firstNonBlank(item.PredictedLiveState, item.TargetState)
	liveRaw := firstNonBlank(item.NormalizedLiveState, item.LiveState)
	resource := resourceRefFromDiff(item, desiredRaw, liveRaw)

	if desiredRaw == "" && liveRaw == "" {
		if !item.Modified {
			return nil
		}
		return []Finding{insufficientEvidenceFinding(resource, observedAt, "Argo CD marked the resource modified but returned no desired or live state.")}
	}

	desired, err := decodeAndNormalizeState(desiredRaw)
	if err != nil {
		return []Finding{insufficientEvidenceFinding(resource, observedAt, "Argo CD desired state could not be decoded for field-level comparison.")}
	}
	live, err := decodeAndNormalizeState(liveRaw)
	if err != nil {
		return []Finding{insufficientEvidenceFinding(resource, observedAt, "Argo CD live state could not be decoded for field-level comparison.")}
	}

	var changes []Change
	switch {
	case desired == nil && live != nil:
		changes = []Change{{Operation: jsondiff.OperationAdd, Path: "", Before: nil, After: live, Confidence: "field-level"}}
	case desired != nil && live == nil:
		changes = []Change{{Operation: jsondiff.OperationRemove, Path: "", Before: desired, After: nil, Confidence: "field-level"}}
	case desired == nil && live == nil:
		return nil
	default:
		patch, compareErr := jsondiff.CompareWithoutMarshal(desired, live)
		if compareErr != nil {
			return []Finding{insufficientEvidenceFinding(resource, observedAt, "Desired and live state could not be compared safely.")}
		}
		for _, operation := range patch {
			if operation.Type != jsondiff.OperationAdd && operation.Type != jsondiff.OperationRemove && operation.Type != jsondiff.OperationReplace {
				continue
			}
			changes = append(changes, Change{
				Operation:  operation.Type,
				Path:       operation.Path,
				Before:     operation.OldValue,
				After:      operation.Value,
				Confidence: "field-level",
			})
		}
	}

	findings := make([]Finding, 0, len(changes))
	for _, change := range changes {
		findings = append(findings, Finding{
			ID:             stableFindingID(resource, change),
			Resource:       resource,
			Change:         change,
			Severity:       "INFO",
			Score:          0,
			Reason:         "Field-level drift was extracted and is awaiting security policy evaluation.",
			Recommendation: "Evaluate the normalized change with the configured RADAR policy set.",
			EvidenceSource: managedResourcesEvidence,
			ObservedAt:     observedAt,
		})
	}
	return findings
}

func decodeAndNormalizeState(raw string) (any, error) {
	if strings.TrimSpace(raw) == "" || strings.TrimSpace(raw) == "null" {
		return nil, nil
	}
	var state any
	decoder := json.NewDecoder(strings.NewReader(raw))
	decoder.UseNumber()
	if err := decoder.Decode(&state); err != nil {
		return nil, err
	}
	normalizeKubernetesObject(state)
	return state, nil
}

func normalizeKubernetesObject(value any) {
	object, ok := value.(map[string]any)
	if !ok {
		return
	}
	delete(object, "status")
	if metadata, ok := object["metadata"].(map[string]any); ok {
		for _, field := range ignoredMetadataFields {
			delete(metadata, field)
		}
	}
}

func resourceRefFromDiff(item argocd.ResourceDiff, states ...string) ResourceRef {
	resource := ResourceRef{Group: item.Group, Kind: item.Kind, Namespace: item.Namespace, Name: item.Name}
	for _, raw := range states {
		if strings.TrimSpace(raw) == "" {
			continue
		}
		var state struct {
			APIVersion string `json:"apiVersion"`
		}
		if json.Unmarshal([]byte(raw), &state) == nil && state.APIVersion != "" {
			parts := strings.SplitN(state.APIVersion, "/", 2)
			if len(parts) == 1 {
				resource.Version = parts[0]
			} else {
				if resource.Group == "" {
					resource.Group = parts[0]
				}
				resource.Version = parts[1]
			}
			break
		}
	}
	return resource
}

func insufficientEvidenceFinding(resource ResourceRef, observedAt time.Time, reason string) Finding {
	change := Change{Operation: "unknown", Path: "unknown", Confidence: "resource-status-only"}
	return Finding{
		ID:             stableFindingID(resource, change),
		Resource:       resource,
		Change:         change,
		Severity:       "INFO",
		Score:          0,
		Reason:         reason,
		Recommendation: "Collect valid field-level desired and live state before assigning security risk.",
		EvidenceSource: managedResourcesEvidence,
		ObservedAt:     observedAt,
	}
}

func stableFindingID(resource ResourceRef, change Change) string {
	payload, _ := json.Marshal(struct {
		Resource ResourceRef `json:"resource"`
		Change   Change      `json:"change"`
	}{Resource: resource, Change: change})
	sum := sha256.Sum256(payload)
	return "RADAR-" + strings.ToUpper(hex.EncodeToString(sum[:6]))
}

func resourceDiffKey(item argocd.ResourceDiff) string {
	return fmt.Sprintf("%s/%s/%s/%s", item.Group, item.Kind, item.Namespace, item.Name)
}

func firstNonBlank(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}
