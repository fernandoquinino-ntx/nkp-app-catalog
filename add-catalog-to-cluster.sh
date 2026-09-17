#!/usr/bin/env bash
# add-catalog-to-cluster.sh — register THIS catalog collection in an NKP workspace
# (creates a Flux OCIRepository that sources the OCI artifact pushed by build-and-push.sh).
#
# Usage:
#   ./add-catalog-to-cluster.sh [--workspace kommander-workspace] [--tag v0.1.0]
#       [--url oci://ghcr.io/<org>/nkp-app-catalog/nkp-app-catalog/collection]
#       [--namespace <ws-ns>] [--kubeconfig <path>] [--nkp nkp] [--dry-run]
#
# Notes:
#   - Creating the catalog in the `kommander` namespace propagates it to ALL workspaces.
#   - The OCI registry must be reachable by the cluster; public GHCR packages need no secret.
set -euo pipefail

REGISTRY_DEFAULT="oci://ghcr.io/fernandoquinino-ntx/nkp-app-catalog"
WS="kommander-workspace"; TAG=""; URL=""; NS=""; KUBECONFIG_ARG=""; NKP="${NKP:-nkp}"; DRY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --workspace)  WS="${2:?}"; shift 2 ;;
    --tag)        TAG="${2:?}"; shift 2 ;;
    --url)        URL="${2:?}"; shift 2 ;;
    --namespace)  NS="${2:?}"; shift 2 ;;
    --kubeconfig) KUBECONFIG_ARG="${2:?}"; shift 2 ;;
    --nkp)        NKP="${2:?}"; shift 2 ;;
    --dry-run)    DRY=1; shift ;;
    -h|--help)    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

command -v "$NKP" >/dev/null || { echo "nkp CLI not found (set NKP=<path> or --nkp)"; exit 1; }
[ -n "$TAG" ] || { echo "--tag is required (e.g. v0.1.0)" >&2; exit 2; }
[ -n "$URL" ] || URL="${REGISTRY_DEFAULT}/nkp-app-catalog/collection"

KUBECTL_ARGS=(); [ -n "$KUBECONFIG_ARG" ] && KUBECTL_ARGS=(--kubeconfig "$KUBECONFIG_ARG")
[ -n "$KUBECONFIG_ARG" ] && export KUBECONFIG="$KUBECONFIG_ARG"

# Resolve the workspace namespace from the Workspace CR (fall back to the workspace name).
if [ -z "$NS" ] && command -v kubectl >/dev/null; then
  NS="$(kubectl "${KUBECTL_ARGS[@]}" get workspace "$WS" -o jsonpath='{.status.namespace}' 2>/dev/null || true)"
  [ -n "$NS" ] || NS="$(kubectl "${KUBECTL_ARGS[@]}" get workspace "$WS" -o jsonpath='{.spec.namespace}' 2>/dev/null || true)"
fi
[ -n "$NS" ] || NS="$WS"

echo "== add catalog collection to NKP =="
echo "   workspace : ${WS}   (namespace ${NS})"
echo "   url       : ${URL}"
echo "   tag       : ${TAG}"

cmd=("$NKP" create catalog-collection --url "$URL" --tag "$TAG" --workspace "$WS")
[ -n "$KUBECONFIG_ARG" ] && cmd+=(--kubeconfig "$KUBECONFIG_ARG")
echo ">> ${cmd[*]}"
if [ "$DRY" = 1 ]; then echo "(dry-run: not executed)"; exit 0; fi
"${cmd[@]}"

echo "== verify =="
if command -v kubectl >/dev/null; then
  kubectl "${KUBECTL_ARGS[@]}" -n "$NS" get ocirepository 2>/dev/null || true
  echo "   (watch it become Ready: kubectl -n ${NS} get ocirepository -w)"
  echo "   rollback: kubectl -n ${NS} delete ocirepository <name>"
fi
echo
echo "done — in the NKP UI: workspace '${WS}' → Applications → the 'nkp-app-catalog' collection."
