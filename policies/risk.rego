package radar.risk

import rego.v1

findings contains decision if {
	decision := critical_rbac_escalation
}

findings contains decision if {
	decision := critical_privileged_container
}

findings contains decision if {
	decision := high_network_policy
}

findings contains decision if {
	decision := high_host_path
}

findings contains decision if {
	decision := high_service_exposure
}

findings contains decision if {
	decision := high_host_namespace
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

critical_rbac_escalation := {
	"severity": "CRITICAL",
	"score": 95,
	"reason": "RBAC drift may expand Kubernetes privileges.",
	"recommendation": "Review the live RBAC object, revert unauthorized privilege expansion, and require approval for privilege-bearing manifests.",
} if {
	is_rbac_kind
	rbac_escalation
}

critical_privileged_container := {
	"severity": "CRITICAL",
	"score": 92,
	"reason": "A container was changed to run in privileged mode.",
	"recommendation": "Disable privileged mode unless there is a documented exception and compensating control.",
} if {
	contains(change_path, "privileged")
	input.change.after == true
}

high_network_policy := {
	"severity": "HIGH",
	"score": 82,
	"reason": "NetworkPolicy drift can weaken workload network isolation.",
	"recommendation": "Restore the intended NetworkPolicy and review the exposure window.",
} if {
	input.resource.kind == "NetworkPolicy"
	lower(input.change.operation) == "delete"
}

high_host_path := {
	"severity": "HIGH",
	"score": 80,
	"reason": "A hostPath volume can expose node filesystem access to a workload.",
	"recommendation": "Remove hostPath unless explicitly required and tightly constrained.",
} if {
	contains(change_path, "hostpath")
}

high_service_exposure := {
	"severity": "HIGH",
	"score": 78,
	"reason": "Service drift exposes the workload through NodePort or LoadBalancer.",
	"recommendation": "Restore the intended Service type or validate that external exposure is approved.",
} if {
	input.resource.kind == "Service"
	exposed_service_type
}

high_host_namespace := {
	"severity": "HIGH",
	"score": 76,
	"reason": "Host namespace sharing increases workload access to node-level context.",
	"recommendation": "Disable hostNetwork, hostPID, or hostIPC unless explicitly approved.",
} if {
	host_namespace_enabled
}

medium_unsafe_image_tag := {
	"severity": "MEDIUM",
	"score": 55,
	"reason": "The workload image changed to an unsafe or weakly controlled image reference.",
	"recommendation": "Use an immutable, trusted image reference and validate registry provenance.",
} if {
	contains(change_path, "image")
	unsafe_image
}

medium_secret_reference := {
	"severity": "MEDIUM",
	"score": 50,
	"reason": "A secret reference changed and may alter sensitive runtime configuration.",
	"recommendation": "Validate the referenced secret and confirm the change was intended.",
} if {
	contains(change_path, "secret")
}

low_metadata_only := {
	"severity": "LOW",
	"score": 20,
	"reason": "Only metadata labels or annotations changed.",
	"recommendation": "Confirm ownership metadata and automation selectors are still correct.",
} if {
	metadata_only_change
}

info_resource_status_only := {
	"severity": "INFO",
	"score": 0,
	"reason": "Argo CD reports resource-level OutOfSync status, but field-level drift details are unavailable.",
	"recommendation": "Collect field-level diff data before assigning security risk.",
} if {
	lower(input.change.operation) == "unknown"
	input.change.confidence == "resource-status-only"
}

is_rbac_kind if {
	{"Role", "ClusterRole", "RoleBinding", "ClusterRoleBinding"}[input.resource.kind]
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
	some rule in object.get(input.change, "after", [])
	some resource in object.get(rule, "resources", [])
	resource == "secrets"
}

rbac_escalation if {
	{"RoleBinding", "ClusterRoleBinding"}[input.resource.kind]
	after := object.get(input.change, "after", {})
	role_ref := object.get(after, "roleRef", {})
	object.get(role_ref, "name", "") == "cluster-admin"
}

rbac_escalation if {
	{"RoleBinding", "ClusterRoleBinding"}[input.resource.kind]
	after := object.get(input.change, "after", {})
	some subject in object.get(after, "subjects", [])
	{"system:masters", "cluster-admin"}[object.get(subject, "name", "")]
}

exposed_service_type if {
	{"NodePort", "LoadBalancer"}[input.change.after]
}

host_namespace_enabled if {
	input.change.after == true
	contains(change_path, "hostnetwork")
}

host_namespace_enabled if {
	input.change.after == true
	contains(change_path, "hostpid")
}

host_namespace_enabled if {
	input.change.after == true
	contains(change_path, "hostipc")
}

unsafe_image if {
	endswith(sprintf("%v", [input.change.after]), ":latest")
}

unsafe_image if {
	image := sprintf("%v", [input.change.after])
	not startswith(image, "registry.example.local/")
	not startswith(image, "ghcr.io/")
	not startswith(image, "docker.io/library/")
}

metadata_only_change if {
	startswith(change_path, "/metadata/labels")
}

metadata_only_change if {
	startswith(change_path, "/metadata/annotations")
}

change_path := lower(object.get(input.change, "path", ""))
