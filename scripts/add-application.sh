#!/usr/bin/env bash
# add-application.sh — add a Helm-based application version to this NKP catalog.
#
# Usage:
#   # chart already published in an OCI registry
#   ./scripts/add-application.sh --appname <name> --version <ver> --ocirepo oci://<registry>/<path>/<chart>
#
#   # chart lives in a Helm repo -> pull it and push it to your OCI registry first
#   ./scripts/add-application.sh --appname <name> --version <ver> \
#       --helmrepo <repo/chart> --ocipush oci://<registry>/<path> [--helmrepo-url https://<helm-repo>]
#
# Options: --force (overwrite existing), --skip-push (do not run `helm push`)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

usage() { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; }

APPNAME=""; VERSION=""; OCIREPO=""; HELMREPO=""; OCIPUSH=""; HELMREPO_URL=""; FORCE=0; SKIP_PUSH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --appname)       APPNAME="${2:?}"; shift 2 ;;
    --version)       VERSION="${2:?}"; shift 2 ;;
    --ocirepo)       OCIREPO="${2:?}"; shift 2 ;;
    --helmrepo)      HELMREPO="${2:?}"; shift 2 ;;
    --ocipush)       OCIPUSH="${2:?}"; shift 2 ;;
    --helmrepo-url)  HELMREPO_URL="${2:?}"; shift 2 ;;
    --force)         FORCE=1; shift ;;
    --skip-push)     SKIP_PUSH=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[ -n "$APPNAME" ] && [ -n "$VERSION" ] || { usage; exit 2; }
command -v helm >/dev/null || { echo "helm required" >&2; exit 1; }

APP_DIR="${REPO_DIR}/applications/${APPNAME}/${VERSION}"
if [ -d "$APP_DIR" ] && [ "$FORCE" != 1 ]; then
  echo "already exists (use --force): $APP_DIR" >&2; exit 1
fi

# ---- resolve the OCI chart URL ------------------------------------------------
CHART_NAME="$(basename "$APPNAME")"
if [ -n "$HELMREPO" ]; then
  [ -n "$OCIPUSH" ] || { echo "--ocipush is required with --helmrepo" >&2; exit 2; }
  if [ -n "$HELMREPO_URL" ]; then
    helm repo add "$(echo "$HELMREPO" | cut -d/ -f1)" "$HELMREPO_URL" >/dev/null
  fi
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  ( cd "$TMP" && helm pull "$HELMREPO" --version "$VERSION" )
  TGZ="$(ls "$TMP"/*.tgz | head -1)"
  if [ "$SKIP_PUSH" != 1 ]; then
    echo ">> helm push $(basename "$TGZ") $OCIPUSH"
    helm push "$TGZ" "$OCIPUSH"
  fi
  OCIREPO="${OCIPUSH%/}/${CHART_NAME}"
elif [ -z "$OCIREPO" ]; then
  echo "provide --ocirepo, or --helmrepo + --ocipush" >&2; usage; exit 2
fi

echo ">> app=${APPNAME} version=${VERSION}"
echo ">> chart OCI = ${OCIREPO}:${VERSION}"

# ---- generate the app layout --------------------------------------------------
mkdir -p "${APP_DIR}/helmrelease"

cat > "${APP_DIR}/metadata.yaml" <<EOF
schema: catalog.nkp.nutanix.com/v1/application-metadata
displayName: ${APPNAME}
allowMultipleInstances: true
category:
  - nkp-app-catalog
  - general
description: |
  ${APPNAME} (chart ${VERSION}). EDIT-ME: one or two sentences about the application.
dependencies: []
overview: |
  **What it is** — EDIT-ME.

  **Highlights**
  - EDIT-ME

  **Documentation:** [link](https://example.com)
scope:
  - workspace
supportLink: https://example.com
type: custom
EOF

cat > "${APP_DIR}/helmrelease.yaml" <<'EOF'
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: ${releaseName}-helmrelease
  namespace: ${releaseNamespace}
spec:
  interval: 6h0m0s
  path: ./helmrelease
  postBuild:
    substitute:
      releaseName: ${releaseName}
      releaseNamespace: ${releaseNamespace}
  prune: true
  retryInterval: 1m0s
  sourceRef:
    kind: OCIRepository
    name: ${releaseName}-source
    namespace: ${releaseNamespace}
  timeout: 1m0s
  wait: true
EOF

cat > "${APP_DIR}/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - helmrelease.yaml
EOF

cat > "${APP_DIR}/helmrelease/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - cm.yaml
  - helmrelease.yaml
EOF

cat > "${APP_DIR}/helmrelease/cm.yaml" <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${releaseName}-config-defaults
  namespace: ${releaseNamespace}
data:
  values.yaml: |
    # EDIT-ME: ${APPNAME} Helm values.
EOF

sed "s#__OCIREPO__#${OCIREPO}#g; s#__VERSION__#${VERSION}#g; s#__APPNAME__#${APPNAME}#g" > "${APP_DIR}/helmrelease/helmrelease.yaml" <<'EOF'
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: ${releaseName}-chart
  namespace: ${releaseNamespace}
spec:
  interval: 6h0m0s
  ref:
    tag: __VERSION__
  url: __OCIREPO__
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: __APPNAME__
  namespace: ${releaseNamespace}
spec:
  chartRef:
    kind: OCIRepository
    name: ${releaseName}-chart
    namespace: ${releaseNamespace}
  install:
    crds: CreateReplace
    createNamespace: true
    remediation:
      retries: 30
  interval: 15s
  targetNamespace: __APPNAME__
  upgrade:
    crds: CreateReplace
    remediation:
      retries: 30
  valuesFrom:
    - kind: ConfigMap
      name: ${releaseName}-config-defaults
EOF

cat > "${APP_DIR}/../.catalog-source.yaml" <<EOF
# Source for \`check-versions\`: chart pulled from this Helm repo, then pushed to OCI.
helmrepo: ${HELMREPO:-}
helmrepoUrl: ${HELMREPO_URL:-}
ocipush: ${OCIPUSH:-}
EOF

echo
echo "created ${APP_DIR}"
echo "next:"
echo "  1. edit ${APP_DIR}/metadata.yaml (displayName/category/description/overview/supportLink)"
echo "  2. edit ${APP_DIR}/helmrelease/cm.yaml (Helm values)"
echo "  3. ./catalog-workflow.sh validate"
echo "  4. ./catalog-workflow.sh build-push --tag vX.Y.Z"
