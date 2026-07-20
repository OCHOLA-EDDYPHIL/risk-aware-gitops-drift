#!/usr/bin/env python3
"""Generate the decision-complete RADAR formal-evaluation protocol manifest."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


SCENARIOS = (
    ("rbac-wildcard", "RADAR-RBAC-WILDCARD", "CRITICAL", 100, "/rules/0/apiGroups/0", "security"),
    ("networkpolicy-removal", "RADAR-NETPOL-REMOVED", "HIGH", 64, "", "security"),
    ("privileged-container", "RADAR-WORKLOAD-PRIVILEGED", "CRITICAL", 100, "/spec/template/spec/containers/0/securityContext/privileged", "security"),
    ("hostpath-addition", "RADAR-VOLUME-HOSTPATH", "HIGH", 60, "/spec/template/spec/volumes/0/hostPath", "security"),
    ("service-exposure", "RADAR-SERVICE-EXPOSURE", "HIGH", 64, "/spec/type", "security"),
    ("unsafe-image-tag", "RADAR-IMAGE-LATEST", "MEDIUM", 36, "/spec/template/spec/containers/0/image", "security"),
    ("secret-reference", "RADAR-SECRET-REFERENCE", "MEDIUM", 32, "/spec/template/spec/containers/0/env/0/valueFrom/secretKeyRef/name", "security"),
    ("metadata-only", "RADAR-METADATA-ONLY", "LOW", 4, "/metadata/labels/app.kubernetes.io~1part-of", "control"),
)


def build_protocol() -> dict:
    runs = []
    for scenario, rule, severity, score, path, label in SCENARIOS:
        for repetition in range(1, 11):
            runs.append(
                {
                    "runId": f"formal-evaluation-v1-{scenario}-r{repetition:02d}",
                    "scenario": scenario,
                    "repetition": repetition,
                    "groundTruth": label,
                    "expectedRule": rule,
                    "expectedSeverity": severity,
                    "expectedScore": score,
                    "expectedPath": path,
                }
            )
    return {
        "protocolVersion": 1,
        "protocolId": "formal-evaluation-v1",
        "collectionId": "formal-evaluation-v1",
        "evidenceSchemaVersion": 4,
        "scenarioCount": 8,
        "repetitionsPerScenario": 10,
        "declaredRunCount": 80,
        "runs": runs,
        "metrics": {
            "detectionAccuracy": "expected security-rule detections divided by 70 declared security runs",
            "falseNegative": "declared security run without its expected security classification",
            "falsePositive": "metadata control classified MEDIUM or higher",
            "exactSeverityAccuracy": "exact expected severity matches divided by completed runs",
            "timeToDetect": "radarCompletedAt minus mutationAt",
            "processingLatency": "radarCompletedAt minus observedAt",
            "explanationCompleteness": "expected finding has resource, change, severity, reason, and recommendation",
            "percentile": "nearest-rank p95 over valid completed timings",
        },
        "restartRules": {
            "materialChange": "A code, policy, risk-matrix, protocol, or material environment change ends this corpus and requires a versioned replacement protocol.",
            "failedRun": "Failed and interrupted runs remain declared results and are never overwritten.",
            "unsafeReset": "Execution stops immediately when the declared baseline cannot be verified.",
            "resume": "An interrupted collection may resume only missing declared run IDs at the same immutable source and environment.",
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    output = args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(build_protocol(), indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
