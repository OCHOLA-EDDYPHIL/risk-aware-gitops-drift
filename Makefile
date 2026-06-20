GOFILES := $(shell find . -name '*.go' -not -path './vendor/*')

.PHONY: fmt fmt-check test build run-example rego-test ci

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

ci: fmt-check test build
	@if command -v opa >/dev/null 2>&1; then \
		$(MAKE) rego-test; \
	else \
		echo "OPA CLI not installed locally; skipping local Rego tests. GitHub Actions installs OPA and runs opa test policies testdata."; \
	fi
