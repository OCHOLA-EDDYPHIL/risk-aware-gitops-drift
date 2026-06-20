package radar.risk

import rego.v1

test_rbac_escalation_is_critical if {
	result := findings with input as data.drift.rbac_escalation
	some finding in result
	finding.severity == "CRITICAL"
	finding.score >= 90
}

test_privileged_container_is_critical if {
	result := findings with input as data.drift.privileged_container
	some finding in result
	finding.severity == "CRITICAL"
	finding.score >= 90
}

test_networkpolicy_removed_is_high if {
	result := findings with input as data.drift.networkpolicy_removed
	some finding in result
	finding.severity == "HIGH"
}

test_hostpath_added_is_high if {
	result := findings with input as data.drift.hostpath_added
	some finding in result
	finding.severity == "HIGH"
}

test_service_exposed_is_high if {
	result := findings with input as data.drift.service_exposed
	some finding in result
	finding.severity == "HIGH"
}

test_unsafe_latest_tag_is_medium if {
	result := findings with input as data.drift.unsafe_image_tag
	some finding in result
	finding.severity == "MEDIUM"
}

test_metadata_label_change_is_low if {
	result := findings with input as data.drift.metadata_label_change
	some finding in result
	finding.severity == "LOW"
}

test_resource_status_only_unknown_drift_is_info if {
	result := findings with input as {
		"id": "RADAR-ARGOCD-001",
		"resource": {"group": "apps", "version": "v1", "kind": "Deployment", "namespace": "demo", "name": "guestbook"},
		"change": {"operation": "unknown", "path": "unknown", "before": null, "after": null, "confidence": "resource-status-only"},
		"evidenceSource": "argocd-application-status",
	}
	some finding in result
	finding.severity == "INFO"
	finding.score == 0
}
