# RADAR Controlled Research Lab

This directory defines the isolated environment used to validate RADAR. It is a synthetic research testbed, not a production cluster. The host can be a local Linux machine, a Linux virtual machine, or a temporary cloud development host. The target cluster is always the dedicated `radar-lab` Minikube profile.

## Pinned environment

| Component | Version or setting |
| --- | --- |
| Minikube | 1.38.1 |
| Kubernetes server | 1.35.1 |
| kubectl client | 1.35.6 |
| Argo CD | 3.4.5 |
| OPA | 1.17.1 |
| Go | 1.24.0 |
| Minikube profile and context | `radar-lab` |
| Driver | Docker |
| Capacity | 2 CPUs, 3 GiB RAM |
| Supported host | Linux with Docker and at least 4 GiB available memory |

Every Kubernetes operation names `radar-lab` and verifies its API server, CA and cluster UID against the Minikube profile identity recorded during setup. A same-named context that points elsewhere is rejected before mutation.

GitHub Codespaces and the included devcontainer are optional host adapters. They are not RADAR components or prerequisites.

Run `make lab-static-check` to lint the scripts, render the baseline, and exercise the wrong-context rejection without creating a cluster.

## Safety prerequisites

Run the non-mutating host check first:

```sh
k8s-lab/scripts/preflight.sh --context radar-lab
```

The preflight checks Linux, Docker, the pinned tools, at least two CPUs, at least 4 GiB of available memory, a clean worktree, and the absence of an existing `radar-lab` profile. It never stops unrelated containers or processes. Install the pinned tools by a method appropriate for the selected host; `.devcontainer/install-tools.sh` is the Ubuntu-based devcontainer adapter.

Create a read-only SSH deploy key for this private repository and keep the private key outside the repository. Do not reuse a personal write-capable key.

```sh
export RADAR_REPO_URL=git@github.com:OCHOLA-EDDYPHIL/risk-aware-gitops-drift.git
export RADAR_REPO_SSH_KEY_FILE=/absolute/path/to/read-only-deploy-key
export RADAR_TARGET_REVISION=<immutable-40-character-commit-sha>
k8s-lab/scripts/setup.sh --context radar-lab
```

Setup preserves the existing kubeconfig current context, installs the pinned Argo CD manifest, configures an API-only least-privilege `radar` account, stores the repository credential only inside `radar-lab`, and writes a short-lived API token to the ignored `.radar-lab-token` file.

`RADAR_TARGET_REVISION` is required and must be an immutable 40-character commit SHA. Before injecting drift, the runner requires the clean worktree, Application target, synchronized revision, latest successful sync operation, captured environment and frozen scanner build to identify that same commit.

## Verify and run

```sh
k8s-lab/scripts/verify-baseline.sh --context radar-lab
k8s-lab/scripts/capture-environment.sh \
  --collection-id runner-integrity-v1 \
  --provider local-linux \
  --output k8s-lab/evidence/runner-integrity-v1/environment.json
k8s-lab/scripts/run-scenario.sh \
  --context radar-lab --collection-id runner-integrity-v1 \
  --scenario privileged-container --repetition 1 \
  --environment-file k8s-lab/evidence/runner-integrity-v1/environment.json
```

Valid scenarios are listed in [drift-scenarios/README.md](drift-scenarios/README.md). Each run builds the scanner from the required files at the clean source commit without retrieving unrelated evidence archives. It applies one live mutation without editing Git, records schema-v3 JSON, deletes and recreates only the synthetic `radar-demo` namespace, and verifies the restored frozen revision and declared baseline.

Use an accurate provider label for the selected host. Cloud-hosted runs can also supply `--region` and `--machine-type`. Those two values are stored as `null` when they do not apply. The older `capture-codespace-environment.sh` command remains as a compatibility wrapper for existing Codespaces procedures.

Local evidence is written below the ignored `k8s-lab/evidence/` directory. Review it before moving selected, sanitized records into any formal research evidence location.

## Frozen formal collection

Formal evaluation uses the decision-complete manifest under `research/protocols/`. The manifest declares all 80 run identifiers and their ground truth before execution. The collection executor runs only the explicit `radar-lab` context, preserves terminal failures, skips an existing run only after validating its declared identity, and stops when reset verification is absent.

The existing `formal-evaluation-v1` corpus is immutable and records GitHub Codespaces because that was its actual execution host. This provenance does not make Codespaces a system dependency. A future formal collection must use `capture-environment.sh`, a new approved protocol, and a matching new collection identifier. Do not write new runs into the existing collection.

Supplying a protocol creates schema-v4 evidence and binds each run to the protocol checksum, predeclared run ID, ground truth and risk-matrix checksum. Omitting it retains schema-v3 qualification behavior. A formal collection must use one immutable source commit and environment; material changes require a versioned replacement rather than continuation.

After all declared runs are sanitized and indexed, `summarize-evaluation.py` derives run accounting, detection, classification, timing and explanation metrics from the reviewable summaries. Generated values never replace or edit the immutable run records.

## Teardown

```sh
k8s-lab/scripts/teardown.sh --context radar-lab --confirm radar-lab
```

Teardown deletes only the Minikube profile named `radar-lab` and its local token file. It does not prune Docker, delete other Minikube profiles, or operate on another Kubernetes context.
