# Adding a new application — step-by-step plan

The repeatable, end-to-end plan to add a new app to this NKP catalog and get it deployable from the
Kommander UI. Follow the phases in order; each one ends with a **verify**.

> Validated with the lab `nkp` CLI (catalog v0.9.1, konvoy/kommander v2.18.0).
> Registry used here: `oci://ghcr.io/fernandoquinino-ntx`.

---

## Phase 0 — Plan (fill this in before touching files)

| Field | Value (example) |
|---|---|
| **App name / dir** | `cert-manager` |
| **Chart source** | Helm repo `jetstack/cert-manager` (or an OCI chart) |
| **Chart version** | `1.19.2` |
| **Chart OCI target** | `oci://ghcr.io/fernandoquinino-ntx/cert-manager/cert-manager` |
| **Deploy namespace** | `cert-manager` |
| **Values / overrides** | enable CRDs, resource requests, … |
| **NKP license tier** | `[Pro, Ultimate]` (or `[]` = any) |
| **Categories** | `nkp-app-catalog` + domain (`security`, `observability`, …) |
| **Dependencies** | other catalog apps it needs (tags only, non-blocking) |
| **Footprint** | replicas, storage (PVC), CPU/mem |

> **Rule:** the app's **Helm chart** must live in its **own** OCI namespace
> (`.../<app>/<app>:<ver>`), *separate* from the catalog bundle (`.../nkp-app-catalog/...`).
> `nkp push bundle` also pushes an app artifact named `<catalog>/<app>:<ver>` — if the chart used the
> same path it would be overwritten.

---

## Phase 1 — Scaffold the app directory

```bash
# Helm-repo chart (pulls + pushes the chart to OCI for you)
./catalog-workflow.sh add-app --appname cert-manager --version 1.19.2 \
  --helmrepo jetstack/cert-manager \
  --ocipush oci://ghcr.io/fernandoquinino-ntx/cert-manager \
  --helmrepo-url https://charts.jetstack.io

# …or a chart already published in OCI
./catalog-workflow.sh add-app --appname cert-manager --version 1.19.2 \
  --ocirepo oci://quay.io/jetstack/charts/cert-manager
```
Creates:
```
applications/<app>/<version>/{metadata.yaml, helmrelease.yaml, kustomization.yaml, helmrelease/{cm.yaml,helmrelease.yaml,kustomization.yaml}}
```
**Verify:** `ls applications/<app>/<version>/` and `grep url: applications/<app>/<version>/helmrelease/helmrelease.yaml`.

---

## Phase 2 — Author `metadata.yaml`

```yaml
schema: catalog.nkp.nutanix.com/v1/application-metadata
displayName: cert-manager
allowMultipleInstances: false
category: [nkp-app-catalog, security, certificates]   # include YOUR catalog name
description: |
  Short (1–2 sentence) description shown on the app card.
dependencies: []
icon: https://…/icon.svg
licensing: [Pro, Ultimate]        # [] = installable on any NKP license
overview: |
  **What it is** — …
  **Highlights**
  - …
  **Documentation:** [docs](https://…) | **Project:** [repo](https://…)
scope: [workspace]
supportLink: https://…
type: custom
```
**Verify:** the schema line is exactly `catalog.nkp.nutanix.com/v1/application-metadata`.

---

## Phase 3 — Author the values (`helmrelease/cm.yaml`)

Set sane, portable defaults in `${releaseName}-config-defaults` → `values.yaml`; document anything a
consumer may override. Avoid embedding cluster-specific secrets/TLS (those are the consumer's job).
**Verify:** `yq e '.data["values.yaml"]' applications/<app>/<version>/helmrelease/cm.yaml`.

---

## Phase 4 — Local validation

```bash
./catalog-workflow.sh validate          # nkp validate catalog-repository --repo-dir=.
```
If it fails `failed to pull oci repository … UNAUTHORIZED`, give nkp registry creds
(`~/.docker/config.json`) or make the chart public first.
**Verify:** `METADATA ✓  APP MANIFESTS ✓` for your app.

---

## Phase 5 — Ensure the chart is in OCI

(Only if you didn't use `--helmrepo` in Phase 1, or to (re)push a specific version.)
```bash
helm registry login ghcr.io -u <owner> --password-stdin
helm pull <repo>/<chart> --version <ver>
helm push <chart>-<ver>.tgz oci://ghcr.io/fernandoquinino-ntx/<app>
```
**Verify:** `helm show chart oci://ghcr.io/fernandoquinino-ntx/<app>/<chart> --version <ver>`.

---

## Phase 6 — Bump, build + push the catalog bundle

```bash
GHCR_USERNAME=<owner> GHCR_PASSWORD=<PAT> \
  ./catalog-workflow.sh build-push --tag v0.2.0
```
Runs `nkp validate` → `nkp create catalog-bundle --collection-tag v0.2.0` → `nkp push bundle --bundle
… --to-registry oci://ghcr.io/<owner>`.
**Verify:** the log shows `nkp-app-catalog/collection:v0.2.0` + `nkp-app-catalog/<app>:<ver>` pushed.

---

## Phase 7 — Make the OCI packages PUBLIC

Container packages are **private by default** and GitHub has **no API** for visibility.
GitHub → repo **Packages** → each package → **Package settings → Danger Zone → Change visibility → Public**.
Packages: `nkp-app-catalog/collection`, `nkp-app-catalog/<app>`, `<app>/<app>` (the chart).
**Verify:** `curl -s "https://ghcr.io/token?scope=repository:<owner>/<app>/<chart>:pull&service=ghcr.io"` returns a token (not `UNAUTHORIZED`).

---

## Phase 8 — Commit + tag (CI)

```bash
git add applications/<app> && git commit -m "feat(<app>): add <app> <version>"
git push origin main
git tag v0.2.0 && git push origin v0.2.0    # triggers the CI publish job (builds/pushes the bundle)
```

---

## Phase 9 — Update the catalog on the cluster (onboard)

```bash
nkp create catalog-collection \
  --url oci://ghcr.io/fernandoquinino-ntx/nkp-app-catalog/collection --tag v0.2.0 \
  --workspace kommander-workspace --kubeconfig <kubeconfig>
# or point the existing source at the new tag:
nkp edit ocirepository -n kommander nkp-app-catalog-collection
```
**Verify:** `kubectl -n kommander get ocirepository nkp-app-catalog-collection` → `READY=True`;
`kubectl -n kommander get apps | grep <app>`.

---

## Phase 10 — Deploy + verify

**UI:** *Applications → <app> → Deploy* (pick workspace/cluster + overrides).
**CLI:**
```bash
nkp create appdeployment <app> --app <app>-<version> \
  --workspace kommander-workspace --kubeconfig <kubeconfig>
```
**Verify:** `<app>` HelmRelease `Ready`; pods Running; the app's namespace/svc reachable.
⚠ If the app's target namespace already holds a workload, the install collides — deploy elsewhere or
change the app's namespace.

---

## Phase 11 — Document the app

Add the app + version to the README "Applications" table and (optionally) a short `docs/` note with
its UI/usage/overrides.

---

## Checklist
- [ ] Phase 0 plan filled in
- [ ] app scaffolded (`applications/<app>/<version>/` with all 4 required files)
- [ ] `metadata.yaml` schema + category `nkp-app-catalog` + overview + supportLink
- [ ] values in `cm.yaml` (portable defaults)
- [ ] `./catalog-workflow.sh validate` passes
- [ ] chart pushed to the **separate** OCI namespace
- [ ] bundle built + pushed (new tag)
- [ ] GHCR packages set **Public**
- [ ] committed + tagged (CI green)
- [ ] collection updated on the cluster (`OCIRepository` Ready, `App/<app>-<ver>` present)
- [ ] deployed + verified in the UI/CLI
- [ ] README/table updated
