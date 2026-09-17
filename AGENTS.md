# AGENTS.md — nkp-app-catalog

Conventions for agents/contributors editing this catalog.

## Golden rules
- **Use the scripts** — `./catalog-workflow.sh add-app|validate|build-push`. Don't hand-roll the flow.
- **Never commit secrets.** `.env.local` (gitignored) holds `GHCR_USERNAME`/`GHCR_PASSWORD`. No PATs in git.
- One application = `applications/<app>/<version>/`; `<version>` is the **Helm chart version**.
- `metadata.yaml` must use `schema: catalog.nkp.nutanix.com/v1/application-metadata` and include the
  category `nkp-app-catalog` plus `displayName`, `description`, `overview`, `supportLink`, `scope`.
- Flux resources in `helmrelease/` use the substitution vars `${releaseName}` / `${releaseNamespace}`.
- Validate before every push: `./catalog-workflow.sh validate`.

## Layout
```
applications/<app>/<version>/
├── metadata.yaml        # catalog metadata (schema above)
├── helmrelease.yaml      # root Flux Kustomization (kustomize.toolkit.fluxcd.io/v1)
├── kustomization.yaml
└── helmrelease/
    ├── helmrelease.yaml   # OCIRepository (chart in OCI) + HelmRelease
    ├── cm.yaml            # ConfigMap ${releaseName}-config-defaults → values.yaml
    └── kustomization.yaml
```

## Add an app
```bash
# chart already in OCI
./catalog-workflow.sh add-app --appname <name> --version <ver> --ocirepo oci://<registry>/<chart>
# chart in a Helm repo → pull + push to OCI first
./catalog-workflow.sh add-app --appname <name> --version <ver> \
  --helmrepo <repo/chart> --ocipush oci://ghcr.io/fernandoquinino-ntx/charts \
  --helmrepo-url https://<helm-repo-url>
```
Then edit `metadata.yaml`, `./catalog-workflow.sh validate`, `./catalog-workflow.sh build-push --tag vX.Y.Z`.

## Registry
OCI: charts go to a chart namespace (`oci://ghcr.io/fernandoquinino-ntx/<chartdir>/<chart>`, e.g. `.../vault/vault`);
the collection bundle under `oci://ghcr.io/fernandoquinino-ntx/nkp-app-catalog/collection`.
