# RADAR Controlled Research Lab

This directory defines the isolated local environment used to validate RADAR. It is a synthetic research testbed, not a production cluster. Fixture results and lab results are separate evidence tiers.

## Pinned environment

| Component | Version or setting |
| --- | --- |
| Minikube | 1.38.1 |
| Kubernetes | 1.35.6 |
| Argo CD | 3.4.5 |
| OPA | 1.17.1 |
| Go | 1.22.12 |
| Minikube profile and context | `radar-lab` |
| Driver | Docker |
| Capacity | 2 CPUs, 3 GiB RAM |

Every `kubectl` invocation in the lab scripts includes `--context radar-lab`. The scripts must never use the workstation current context implicitly.

Run `make lab-static-check` to lint the scripts, render the baseline, and exercise the wrong-context rejection without creating a cluster.

## Safety prerequisites

The setup script fails unless at least 4 GiB of host memory is available. Close applications yourself if the preflight fails; the script never stops unrelated containers or processes.

Create a read-only SSH deploy key for this private repository and keep the private key outside the repository. Do not reuse a personal write-capable key.

```sh
export RADAR_REPO_URL=git@github.com:OCHOLA-EDDYPHIL/risk-aware-gitops-drift.git
export RADAR_REPO_SSH_KEY_FILE=/absolute/path/to/read-only-deploy-key
k8s-lab/scripts/setup.sh --context radar-lab
```

Setup preserves the existing kubeconfig current context, installs the pinned Argo CD manifest, configures an API-only least-privilege `radar` account, stores the repository credential only inside `radar-lab`, and writes a short-lived API token to the ignored `.radar-lab-token` file.

`RADAR_TARGET_REVISION` defaults to `main` for environment setup. Controlled runs must use the immutable commit SHA recorded by the evaluation protocol.

## Verify and run

```sh
k8s-lab/scripts/verify-baseline.sh --context radar-lab
k8s-lab/scripts/run-scenario.sh --context radar-lab --scenario privileged-container --repetition 1
```

Valid scenarios are listed in [drift-scenarios/README.md](drift-scenarios/README.md). Each run refuses a dirty baseline, applies one live mutation without editing Git, records sanitized JSON, deletes and recreates only the synthetic `radar-demo` namespace, and verifies the restored baseline.

Local evidence is written below the ignored `k8s-lab/evidence/` directory. Review it before moving selected, sanitized records into any formal research evidence location.

## Teardown

```sh
k8s-lab/scripts/teardown.sh --context radar-lab --confirm radar-lab
```

Teardown deletes only the Minikube profile named `radar-lab` and its local token file. It does not prune Docker, delete other Minikube profiles, or operate on another Kubernetes context.
