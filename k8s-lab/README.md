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

## 1. Create the isolated project environment

The host needs Linux x86-64, a working Docker daemon, Git, `curl`, Python
3.10–3.14 with venv support, `tar`, `xz`, and SHA-256 utilities. The live lab additionally
needs at least two CPUs and 4 GiB of currently available memory.

From the repository root:

```sh
make env-bootstrap
source scripts/activate-env.sh
make env-check
```

The bootstrap verifies every downloaded archive or binary and installs all
project tools below the ignored `.radar-env` directory. It does not use `sudo`
or modify `/usr/local`. Activation also isolates Go caches, Python packages,
Minikube state, kubeconfig, and generated credentials. Repeat only the `source`
command in each new shell; use `radar-deactivate` when finished.

The included devcontainer runs the same bootstrap contract. It is an optional
convenience, not a requirement.

Run `make lab-static-check` to lint the scripts, render the baseline, and
exercise wrong-context rejection without creating a cluster.

## 2. Prepare repository access

Argo CD must read the exact Git commit used by the checkout. Make sure the
working tree is clean, the commit has been pushed to the remote, and a
read-only SSH deploy key for this repository exists outside the checkout. Do
not reuse a personal write-capable key.

```sh
git status --short
export RADAR_REPO_URL=git@github.com:OCHOLA-EDDYPHIL/risk-aware-gitops-drift.git
export RADAR_REPO_SSH_KEY_FILE=/absolute/path/to/read-only-deploy-key
export RADAR_TARGET_REVISION="$(git rev-parse HEAD)"
chmod 600 "${RADAR_REPO_SSH_KEY_FILE}"
```

`RADAR_TARGET_REVISION` must be an immutable 40-character commit SHA. The
runner later requires the checkout, Argo CD target, synchronized revision, and
latest successful synchronization to identify this same commit.

## 3. Create the dedicated cluster

Run the non-mutating preflight, then setup:

```sh
make lab-preflight
make lab-setup
```

The preflight verifies the activated project environment, Linux, Docker, pinned
tool versions, capacity, clean worktree, and absence of an existing
`radar-lab` profile. It never stops unrelated containers or processes.

Setup creates only the isolated `radar-lab` Minikube profile, installs pinned
Kubernetes and Argo CD versions, synchronizes the synthetic baseline, and
verifies it. The deploy key is stored only in that cluster. Setup creates:

- an API-token account used by the RADAR CLI;
- a separate browser-login account named `radar-viewer`;
- identical read-only access for only the `radar/radar-lab` Application and
  project; and
- mode-`0600` credentials below `.radar-env/state/`.

After provisioning, setup disables the Argo CD bootstrap administrator and
removes its initial password Secret.

## 4. Rehearse the visual demonstration

Use two terminals. In both, enter the repository and run:

```sh
source scripts/activate-env.sh
```

In terminal A, start the localhost-only Argo CD UI tunnel:

```sh
make lab-ui
```

Open the printed URL and sign in as `radar-viewer`. Read the password from the
printed mode-`0600` file without placing it in notes, screenshots, shell
history, or the repository. Keep this terminal running.

If the lab is on a remote host, carry the printed loopback port through a
trusted SSH or editor tunnel. Do not publish Argo CD on a public interface.

In terminal B, start the guided rehearsal:

```sh
make lab-demo
```

The script pauses at each presentation checkpoint and safely demonstrates one
synthetic privileged-container drift:

1. Show the Application as `Synced` and `Healthy` in Argo CD.
2. Continue; the script changes only the synthetic Deployment and waits for
   Argo CD to report `OutOfSync`.
3. Refresh the browser, open the Deployment diff, and point to
   `privileged: true`.
4. Continue; RADAR reads the same Argo CD evidence and prints the exact field,
   before/after values, explanation, and `CRITICAL / 100` decision.
5. Contrast Argo CD's drift status with RADAR's security interpretation, then
   continue; the script explicitly synchronizes and verifies the baseline.
6. Refresh the browser and show `Synced` and `Healthy` again.

If the rehearsal is interrupted after mutation, its exit handler attempts the
same verified baseline reset before stopping. This is a visual demonstration,
not a new formal evaluation result.

## Controlled evidence runs

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

## 5. Teardown

```sh
make lab-teardown
```

Teardown deletes only the project-local Minikube profile named `radar-lab` and
its project-local API token and browser password. It does not prune Docker,
delete another Minikube profile, inspect a system kubeconfig, or operate on
another Kubernetes context.
