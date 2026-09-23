GOFILES := $(shell find . -name '*.go' -not -path './vendor/*')
LAB_SCRIPTS := $(shell find k8s-lab/scripts -name '*.sh' -type f | sort)
VERSION ?= dev
COMMIT ?= $(shell git rev-parse --short=12 HEAD 2>/dev/null || printf unknown)
BUILD_DATE ?= $(shell git show -s --format=%cI HEAD 2>/dev/null || printf unknown)
LDFLAGS := -s -w -X github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift/internal/version.Version=$(VERSION) -X github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift/internal/version.Commit=$(COMMIT) -X github.com/OCHOLA-EDDYPHIL/risk-aware-gitops-drift/internal/version.Date=$(BUILD_DATE)

.PHONY: fmt fmt-check vet test race build run-example rego-test policy-integration-test protocol-check lab-static-check release-check release-snapshot docs-check ci

fmt:
	gofmt -w $(GOFILES)

fmt-check:
	@test -z "$$(gofmt -l $(GOFILES))" || (gofmt -l $(GOFILES); exit 1)

test:
	go test ./...

vet:
	go vet ./...

race:
	go test -race ./...

build:
	mkdir -p bin
	go build -trimpath -ldflags "$(LDFLAGS)" -o bin/radar ./cmd/radar

run-example:
	go run ./cmd/radar scan --fixture testdata/argocd/scan_bundle_privileged.json --output table

rego-test:
	@command -v opa >/dev/null 2>&1 || (echo "OPA CLI is required for policy tests. Install OPA or rely on GitHub Actions, which installs it in CI."; exit 1)
	opa test --ignore argocd policies testdata

policy-integration-test:
	@command -v opa >/dev/null 2>&1 || (echo "OPA CLI is required for managed-resource policy integration tests."; exit 1)
	go test ./cmd/radar -run '^TestRunScanScenarioBundlesWithRealOPA$$'

protocol-check:
	@temporary="$$(mktemp)"; trap 'rm -f "$$temporary"' EXIT; \
		python3 k8s-lab/scripts/generate-formal-protocol.py "$$temporary"; \
		cmp "$$temporary" research/protocols/formal-evaluation-v1.json
	python3 k8s-lab/scripts/run_collection_test.py
	python3 k8s-lab/scripts/summarize_evaluation_test.py

lab-static-check:
	@command -v shellcheck >/dev/null 2>&1 || (echo "shellcheck is required for lab script validation."; exit 1)
	@command -v kubectl >/dev/null 2>&1 || (echo "kubectl is required for Kustomize validation."; exit 1)
	python3 k8s-lab/scripts/sanitize_evidence_test.py
	python3 k8s-lab/scripts/validate_evidence_test.py
	python3 k8s-lab/scripts/verify_baseline_test.py
	$(MAKE) protocol-check
	bash k8s-lab/scripts/capture_environment_test.sh
	bash k8s-lab/scripts/common_test.sh
	bash -n $(LAB_SCRIPTS)
	shellcheck $(LAB_SCRIPTS)
	kubectl kustomize k8s-lab/baseline >/dev/null
	@! k8s-lab/scripts/setup.sh --context not-radar-lab >/dev/null 2>&1
	@! k8s-lab/scripts/preflight.sh --context not-radar-lab >/dev/null 2>&1
	@! k8s-lab/scripts/run-scenario.sh --context not-radar-lab --scenario privileged-container --repetition 1 >/dev/null 2>&1
	@! RADAR_BIN=/bin/true k8s-lab/scripts/run-scenario.sh --context radar-lab --collection-id test-run --scenario privileged-container --repetition 1 --environment-file /nonexistent >/dev/null 2>&1

docs-check:
	python3 scripts/check-doc-links.py

release-check:
	@temporary="$$(mktemp --directory)"; trap 'rm -rf "$$temporary"' EXIT; \
		DIST_DIR="$$temporary" scripts/package-release.sh 0.0.0-test; \
		(cd "$$temporary" && sha256sum --check SHA256SUMS); \
		for archive in "$$temporary"/*.tar.gz; do \
			tar -tzf "$$archive" | grep -Eq '/radar$$'; \
			tar -tzf "$$archive" | grep -Eq '/policies/risk.rego$$'; \
			tar -tzf "$$archive" | grep -Eq '/THIRD_PARTY_NOTICES.md$$'; \
		done; \
		native_arch="$$(go env GOARCH)"; \
		if test -f "$$temporary/radar_0.0.0-test_linux_$${native_arch}.tar.gz"; then \
			tar -xzf "$$temporary/radar_0.0.0-test_linux_$${native_arch}.tar.gz" -C "$$temporary"; \
			"$$temporary/radar_0.0.0-test_linux_$${native_arch}/radar" version | grep -Eq '^radar 0\.0\.0-test \([0-9a-f]{40}, .+\)$$'; \
		fi

release-snapshot:
	@test "$(VERSION)" != dev || (echo "VERSION must be an explicit semantic version" >&2; exit 1)
	DIST_DIR="$${DIST_DIR:-dist}" scripts/package-release.sh "$(VERSION)"

ci: fmt-check vet test race build docs-check release-check
	@if command -v opa >/dev/null 2>&1; then \
		$(MAKE) rego-test; \
	else \
		echo "OPA CLI not installed locally; skipping local Rego tests. GitHub Actions installs OPA and runs opa test policies testdata."; \
	fi
