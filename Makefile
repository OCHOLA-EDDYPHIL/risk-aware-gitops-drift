GOFILES := $(shell find . -name '*.go' -not -path './vendor/*')
LAB_SCRIPTS := $(shell find k8s-lab/scripts -name '*.sh' -type f | sort)

.PHONY: fmt fmt-check test build run-example rego-test lab-static-check ci

fmt:
	gofmt -w $(GOFILES)

fmt-check:
	@test -z "$$(gofmt -l $(GOFILES))" || (gofmt -l $(GOFILES); exit 1)

test:
	go test ./...

build:
	go build ./cmd/radar

run-example:
	go run ./cmd/radar scan --fixture testdata/argocd/application_outofsync.json --output table

rego-test:
	@command -v opa >/dev/null 2>&1 || (echo "OPA CLI is required for policy tests. Install OPA or rely on GitHub Actions, which installs it in CI."; exit 1)
	opa test policies testdata

lab-static-check:
	@command -v shellcheck >/dev/null 2>&1 || (echo "shellcheck is required for lab script validation."; exit 1)
	@command -v kubectl >/dev/null 2>&1 || (echo "kubectl is required for Kustomize validation."; exit 1)
	python3 k8s-lab/scripts/sanitize_evidence_test.py
	python3 k8s-lab/scripts/verify_baseline_test.py
	bash -n $(LAB_SCRIPTS)
	shellcheck $(LAB_SCRIPTS)
	kubectl kustomize k8s-lab/baseline >/dev/null
	@! k8s-lab/scripts/setup.sh --context not-radar-lab >/dev/null 2>&1
	@! k8s-lab/scripts/run-scenario.sh --context not-radar-lab --scenario privileged-container --repetition 1 >/dev/null 2>&1

ci: fmt-check test build
	@if command -v opa >/dev/null 2>&1; then \
		$(MAKE) rego-test; \
	else \
		echo "OPA CLI not installed locally; skipping local Rego tests. GitHub Actions installs OPA and runs opa test policies testdata."; \
	fi
