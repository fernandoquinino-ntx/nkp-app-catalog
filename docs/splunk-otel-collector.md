# Splunk OpenTelemetry Collector (catalog app)

Catalog app `splunk-otel-collector` (chart `0.160.0`). Ships pod/container logs **and** host logs
(kube-apiserver audit + `journald`) to **Splunk Cloud HEC**. It does **not** touch Loki/Fluent Bit —
it reads the same node sources and dual-ships.

## What you must set when deploying

| Value | Where | Notes |
|---|---|---|
| `splunkPlatform.endpoint` | ConfigMap / UI override | `https://<stack>.splunkcloud.com:8088/services/collector/event` |
| `splunkPlatform.index` | ConfigMap / UI override | **Must be allowed by the HEC token** |
| HEC token | `Secret <releaseName>-hec` (key `token`) | Recommended; or `splunkPlatform.token` |
| `clusterName` | ConfigMap / UI override | NKP/Kommander cluster name. The chart's schema requires a non-empty value, so the default is an `EDIT-ME-…` placeholder — override it. |

### ⚠ The index must be in the token's "Selected Allowed Indexes"

Splunk Cloud enforces the token's allowed indexes. An unallowed index (e.g. `main` on many trial
tokens) makes HEC return `HTTP 400 {"text":"Incorrect index","code":7}` and the collector
**silently drops every event** — the DaemonSet still looks `Ready`. The chart's values schema
requires a non-empty `splunkPlatform.index`, so there is no "omit the index" fallback.

Pick the allowed index (Splunk UI → **Settings → Data inputs → HTTP Event Collector → (token)**).

### ⚠ TLS: keep `insecureSkipVerify: true`

The Splunk Cloud HEC endpoint serves `CN=SplunkServerDefaultCert` (issuer `SplunkCommonCA`), which is
**not publicly trusted** — strict verification fails from any host. The default sets
`insecureSkipVerify: true`. To verify properly, trust the `SplunkCommonCA` chain in the collector.

## Token via Secret (recommended)

The HelmRelease references an **optional** Secret `<releaseName>-hec` (key `token`), so the token
never has to live in the AppDeployment config:

```bash
# workspaceNamespace = the workspace where the app is deployed (e.g. kommander-workspace)
kubectl -n <workspaceNamespace> create secret generic <releaseName>-hec \
  --from-literal=token='<HEC-TOKEN>'
```

`<releaseName>` is the app release name assigned by the deployment (often the app name). If the
Secret is absent the deploy still succeeds — then set `splunkPlatform.token` in the ConfigMap /
Kommander override instead.

## Verify

```bash
kubectl -n splunk-otel get ds,deploy
# agent pods are labelled app=splunk-otel-collector — there must be NO export drops:
kubectl -n splunk-otel logs -l app=splunk-otel-collector --tail=2000 | grep -c 'Dropping data'   # 0
```

Then in the Splunk UI (Splunk Cloud does **not** expose the management REST `:8089`, so no
programmatic search):

```
index=<your-index> earliest=-15m | stats count by k8s.cluster.name
```

## Metrics (optional)

Set `splunkPlatform.metricsEnabled: true` **and** `clusterReceiver.enabled: true`, and provide a
**metrics-type** index (Cloud-side creation) in `splunkPlatform.metricsIndex`.

## Sizing / uninstall

- DaemonSet on every Linux node: `200m/256Mi` requests, `1/512Mi` limits by default.
- Uninstall: remove the AppDeployment (Flux prunes the release); the namespace `splunk-otel` is
  created by the chart (`createNamespace: true`) and can be deleted manually.

## ⚠ Collision with a script-based deploy

The HelmRelease installs release **`splunk-otel-collector` in namespace `splunk-otel`** — the same
name/namespace the `nkp-deployer` script (`configure/splunk/scripts/configure-splunk-otel.sh`) uses.
Do not keep both on the same cluster: uninstall one first, or deploy the catalog app to a different
namespace, otherwise the Helm releases clash.

## Publishing the packages (one-time, per new app)

Pushing to GHCR creates the packages **private**. The catalog collection package is already public,
but for a new app you must flip **two** packages to Public (GitHub has no API for this):

- `nkp-app-catalog/<app>` — the app artifact the collection references
- `<app>/<app>` — the Helm chart OCI namespace

GitHub → *your packages* → each → **Package settings → Change visibility → Public**.
Verify anonymous pull works (should return a token, not `UNAUTHORIZED`):

```bash
curl -s "https://ghcr.io/token?scope=repository:fernandoquinino-ntx/nkp-app-catalog/splunk-otel-collector:pull&service=ghcr.io"
```

