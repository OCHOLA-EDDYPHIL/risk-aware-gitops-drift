package radar.risk

import rego.v1

findings contains decision if {
	decision := critical_rbac_escalation
}

findings contains decision if {
	decision := critical_privileged_container
}

findings contains decision if {
	decision := high_network_policy_removed
}

findings contains decision if {
	decision := high_host_path_added
}

findings contains decision if {
	decision := high_service_exposure
}

findings contains decision if {
	decision := medium_unsafe_image_tag
}

findings contains decision if {
	decision := medium_secret_reference
}

findings contains decision if {
	decision := low_metadata_only
}

findings contains decision if {
	decision := info_resource_status_only
}

critical_rbac_escalation := decision(
	"RADAR-RBAC-WILDCARD", 5, 5,
	"RBAC drift expands a Role or ClusterRole with wildcard privileges.",
	"Revert the wildcard permission and require review for privilege-bearing RBAC manifests.",
) if {
	is_rbac_kind
	rbac_escalation
}

critical_privileged_container := decision(
	"RADAR-WORKLOAD-PRIVILEGED", 5, 5,
	"A workload container was changed to run in privileged mode.",
	"Disable privileged mode unless a documented exception and compensating controls exist.",
) if {
	contains(change_path, "/securitycontext/privileged")
	valid_change_operation
	input.change.after == true
}

high_network_policy_removed := decision(
	"RADAR-NETPOL-REMOVED", 4, 4,
	"The live cluster no longer contains an intended NetworkPolicy.",
	"Restore the intended NetworkPolicy and review the period without the declared isolation control.",
) if {
	input.resource.kind == "NetworkPolicy"
	lower(input.change.operation) == "remove"
	input.change.path == ""
}

high_host_path_added := decision(
	"RADAR-VOLUME-HOSTPATH", 5, 3,
	"A hostPath volume was added and can expose node filesystem paths to a workload.",
	"Remove hostPath unless it is explicitly required and constrained to the minimum safe path and permissions.",
) if {
	contains(change_path, "/hostpath")
	{"add", "replace"}[lower(input.change.operation)]
	input.change.after != null
}

high_service_exposure := decision(
	"RADAR-SERVICE-EXPOSURE", 4, 4,
	"The Service changed from ClusterIP to a type that expands workload exposure.",
	"Restore ClusterIP or confirm that the broader exposure is approved and protected.",
) if {
	input.resource.kind == "Service"
	change_path == "/spec/type"
	input.change.before == "ClusterIP"
	{"NodePort", "LoadBalancer"}[input.change.after]
}

medium_unsafe_image_tag := decision(
	"RADAR-IMAGE-LATEST", 3, 3,
	"A versioned workload image changed to the mutable latest tag.",
	"Restore an immutable version or digest and verify the intended image provenance.",
) if {
	endswith(change_path, "/image")
	valid_change_operation
	not endswith(lower(sprintf("%v", [input.change.before])), ":latest")
	endswith(lower(sprintf("%v", [input.change.after])), ":latest")
}

medium_secret_reference := decision(
	"RADAR-SECRET-REFERENCE", 4, 2,
	"A workload Secret reference changed and may alter the credential or sensitive configuration path.",
	"Validate the referenced Secret and confirm that the change was reviewed and intended.",
) if {
	contains(change_path, "/secret")
	{"add", "replace"}[lower(input.change.operation)]
	input.change.after != null
	input.change.before != input.change.after
}

low_metadata_only := decision(
	"RADAR-METADATA-ONLY", 1, 1,
	"Only a metadata label or annotation changed, with minimal direct security impact in the selected model.",
	"Confirm that ownership labels and automation selectors remain correct.",
) if {
	metadata_only_change
	valid_change_operation
}

info_resource_status_only := {
	"ruleId": "RADAR-INSUFFICIENT-EVIDENCE",
	"impact": 0,
	"likelihood": 0,
	"severity": "INFO",
	"score": 0,
	"reason": "Argo CD reports resource-level drift but field-level evidence is unavailable.",
	"recommendation": "Collect valid field-level desired and live state before assigning security risk.",
} if {
	lower(object.get(input.change, "operation", "")) == "unknown"
	object.get(input.change, "confidence", "") == "resource-status-only"
}

decision(rule_id, impact, likelihood, reason, recommendation) := {
	"ruleId": rule_id,
	"impact": impact,
	"likelihood": likelihood,
	"severity": severity_for_score(score),
	"score": score,
	"reason": reason,
	"recommendation": recommendation,
} if {
	score := (impact * likelihood) * 4
}

severity_for_score(score) := "CRITICAL" if score >= 80

severity_for_score(score) := "HIGH" if {
	score >= 50
	score < 80
}

severity_for_score(score) := "MEDIUM" if {
	score >= 20
	score < 50
}

severity_for_score(score) := "LOW" if {
	score >= 1
	score < 20
}

severity_for_score(0) := "INFO"

valid_change_operation if {
	{"add", "remove", "replace"}[lower(object.get(input.change, "operation", ""))]
}

is_rbac_kind if {
	{"Role", "ClusterRole", "RoleBinding", "ClusterRoleBinding"}[input.resource.kind]
}

rbac_escalation if {
	contains(change_path, "/rules")
	input.change.after == "*"
}

rbac_escalation if {
	some rule in object.get(input.change, "after", [])
	some verb in object.get(rule, "verbs", [])
	verb == "*"
}

rbac_escalation if {
	some rule in object.get(input.change, "after", [])
	some resource in object.get(rule, "resources", [])
	resource == "*"
}

rbac_escalation if {
	{"RoleBinding", "ClusterRoleBinding"}[input.resource.kind]
	endswith(change_path, "/roleref/name")
	input.change.after == "cluster-admin"
}

metadata_only_change if startswith(change_path, "/metadata/labels")
metadata_only_change if startswith(change_path, "/metadata/annotations")

change_path := lower(object.get(input.change, "path", ""))
