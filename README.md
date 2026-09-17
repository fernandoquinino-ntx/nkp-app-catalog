# nkp-app-catalog

A **public custom application catalog** for [Nutanix Kubernetes Platform (NKP)](https://www.nutanix.com/products/kubernetes-platform).
Applications are Flux/Kustomize manifests + catalog metadata, packaged as an **OCI artifact** and registered in NKP
as a **catalog collection** (a Flux `OCIRepository` in a workspace).

## Applications

| Category | Apps |
|---|---|
| **Security / Secrets** | **Vault** — HashiCorp Vault, HA Raft (`hashicorp/vault` chart 0.34.1) |

## Prerequisites

- [`nkp`](https://github.com/nutanix-cloud-native/nkp) CLI
- [`helm`](https://helm.sh/docs/intro/install/) 3.8+
- an OCI registry you can push to — this repo uses **GHCR**: `oci://ghcr.io/fernandoquinino-ntx/nkp-app-catalog`
- a registry login (a PAT with `write:packages`), e.g. `helm registry login ghcr.io`

## Quick start

```bash
# validate the catalog (nkp validate catalog-repository)
./catalog-workflow.sh validate

# build + push the catalog bundle to GHCR
GHCR_USERNAME=<you> GHCR_PASSWORD=<PAT> ./catalog-workflow.sh build-push --tag v0.1.0

# register the catalog in an NKP workspace (the onboarding step)
./add-catalog-to-cluster.sh --workspace kommander-workspace --tag v0.1.0
```

## Adding an application

```bash
# Helm chart already published in OCI
./catalog-workflow.sh add-app --appname <name> --version <ver> --ocirepo oci://<registry>/<path>/<chart>

# Helm chart in a Helm repo -> pull + push to OCI first
./catalog-workflow.sh add-app --appname <name> --version <ver> \
  --helmrepo <repo/chart> --ocipush oci://ghcr.io/fernandoquinino-ntx/nkp-app-catalog \
  [--helmrepo-url https://<helm-repo-url>]
```

Then edit `applications/<app>/<version>/metadata.yaml` (include category `nkp-app-catalog` +
`description`/`overview`/`supportLink`), run `./catalog-workflow.sh validate`, then `build-push`.

## Structure

```
applications/<app>/<version>/
├── metadata.yaml       # schema: catalog.nkp.nutanix.com/v1/application-metadata
├── helmrelease.yaml    # root Flux Kustomization (kustomize.toolkit.fluxcd.io/v1)
├── kustomization.yaml
└── helmrelease/        # Flux resources
    ├── helmrelease.yaml   # OCIRepository (OCI chart) + HelmRelease
    ├── cm.yaml            # ConfigMap with Helm values (optional)
    └── kustomization.yaml
```

## How it works — the NKP catalog flow

1. `nkp validate catalog-repository --repo-dir=.`
2. `nkp create catalog-bundle --collection-tag <tag>` → `<repo>-<tag>.tar`
3. `nkp push bundle <tar> --to-registry oci://ghcr.io/fernandoquinino-ntx/nkp-app-catalog --to-registry-username … --to-registry-password …`
4. Make the GHCR packages **public** (container packages default private) so clusters pull without a secret.
5. `nkp create catalog-collection --url oci://ghcr.io/fernandoquinino-ntx/nkp-app-catalog/<repo>/collection --tag <tag> --workspace <ws>`
   — created in the `kommander` namespace it propagates to **all** workspaces.

`add-catalog-to-cluster.sh` wraps step 5 (and verifies the resulting `OCIRepository`).

## Security

Never commit credentials. `.env.local` (gitignored) holds `GHCR_USERNAME` / `GHCR_PASSWORD`.
