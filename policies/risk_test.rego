package radar.risk

import rego.v1

test_rbac_escalation_exact_decision if {
	assert_single_decision(data.drift.rbac_escalation, "RADAR-RBAC-WILDCARD", "CRITICAL", 100)
}

test_privileged_container_exact_decision if {
	assert_single_decision(data.drift.privileged_container, "RADAR-WORKLOAD-PRIVILEGED", "CRITICAL", 100)
}

test_networkpolicy_removed_exact_decision if {
	assert_single_decision(data.drift.networkpolicy_removed, "RADAR-NETPOL-REMOVED", "HIGH", 64)
}

test_hostpath_added_exact_decision if {
	assert_single_decision(data.drift.hostpath_added, "RADAR-VOLUME-HOSTPATH", "HIGH", 60)
}

test_service_exposed_exact_decision if {
	assert_single_decision(data.drift.service_exposed, "RADAR-SERVICE-EXPOSURE", "HIGH", 64)
}

test_unsafe_latest_tag_exact_decision if {
	assert_single_decision(data.drift.unsafe_image_tag, "RADAR-IMAGE-LATEST", "MEDIUM", 36)
}

test_secret_reference_exact_decision if {
	assert_single_decision(data.drift.secret_reference, "RADAR-SECRET-REFERENCE", "MEDIUM", 32)
}

test_metadata_label_exact_decision if {
	assert_single_decision(data.drift.metadata_label_change, "RADAR-METADATA-ONLY", "LOW", 4)
}

test_resource_status_only_exact_decision if {
	assert_single_decision(
		{
			"resource": {"kind": "Deployment"},
			"change": {"operation": "unknown", "path": "unknown", "confidence": "resource-status-only"},
		},
		"RADAR-INSUFFICIENT-EVIDENCE", "INFO", 0,
	)
}

test_privileged_false_does_not_match if {
	result := findings with input as {
		"resource": {"kind": "Deployment"},
		"change": {"operation": "replace", "path": "/spec/template/spec/containers/0/securityContext/privileged", "before": true, "after": false},
	}
	count(result) == 0
}

test_rbac_non_wildcard_does_not_match if {
	result := findings with input as {
		"resource": {"kind": "Role"},
		"change": {"operation": "replace", "path": "/rules/0/verbs/0", "before": "get", "after": "list"},
	}
	count(result) == 0
}

test_cluster_admin_binding_is_covered if {
	result := findings with input as {
		"resource": {"kind": "RoleBinding"},
		"change": {"operation": "replace", "path": "/roleRef/name", "before": "view", "after": "cluster-admin"},
	}
	count(result) == 1
	some finding in result
	finding.ruleId == "RADAR-RBAC-WILDCARD"
}

test_unrelated_resource_removal_is_not_networkpolicy if {
	result := findings with input as {
		"resource": {"kind": "ConfigMap"},
		"change": {"operation": "remove", "path": "", "before": {"kind": "ConfigMap"}, "after": null},
	}
	count(result) == 0
}

test_non_hostpath_volume_does_not_match if {
	result := findings with input as {
		"resource": {"kind": "Deployment"},
		"change": {"operation": "add", "path": "/spec/template/spec/volumes/0/emptyDir", "before": null, "after": {}},
	}
	count(result) == 0
}

test_service_exposure_requires_clusterip_before if {
	result := findings with input as {
		"resource": {"kind": "Service"},
		"change": {"operation": "replace", "path": "/spec/type", "before": "NodePort", "after": "LoadBalancer"},
	}
	count(result) == 0
}

test_loadbalancer_exposure_is_covered if {
	result := findings with input as {
		"resource": {"kind": "Service"},
		"change": {"operation": "replace", "path": "/spec/type", "before": "ClusterIP", "after": "LoadBalancer"},
	}
	count(result) == 1
	some finding in result
	finding.ruleId == "RADAR-SERVICE-EXPOSURE"
}

test_versioned_image_does_not_match if {
	result := findings with input as {
		"resource": {"kind": "Deployment"},
		"change": {"operation": "replace", "path": "/spec/template/spec/containers/0/image", "before": "example/app:1.0", "after": "example/app:1.1"},
	}
	count(result) == 0
}

test_secret_reference_removal_does_not_match if {
	result := findings with input as {
		"resource": {"kind": "Deployment"},
		"change": {"operation": "remove", "path": "/spec/template/spec/containers/0/env/0/valueFrom/secretKeyRef/name", "before": "old-secret", "after": null},
	}
	count(result) == 0
}

test_malformed_input_has_no_security_decision if {
	result := findings with input as {"resource": {}, "change": {}}
	count(result) == 0
}

test_overlapping_path_returns_both_decisions if {
	result := findings with input as {
		"resource": {"kind": "Deployment"},
		"change": {"operation": "add", "path": "/spec/template/spec/volumes/0/hostPath/secret", "before": null, "after": "dummy-secret"},
	}
	count(result) == 2
	some hostpath in result
	hostpath.ruleId == "RADAR-VOLUME-HOSTPATH"
	some secret in result
	secret.ruleId == "RADAR-SECRET-REFERENCE"
}

assert_single_decision(input_value, rule_id, severity, score) if {
	result := findings with input as input_value
	count(result) == 1
	some finding in result
	finding.ruleId == rule_id
	finding.severity == severity
	finding.score == score
	(finding.impact * finding.likelihood) * 4 == score
}
