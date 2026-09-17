#!/usr/bin/env bash
# build-and-push.sh — validate, bundle and push this catalog to an OCI registry (GHCR).
#
# Usage: ./scripts/build-and-push.sh <tag>          (e.g. v0.1.0)
# Env (or .env.local):
#   GHCR_USERNAME   registry user (github login)
#   GHCR_PASSWORD   PAT with write:packages (+ delete:packages for MAKE_PUBLIC)
#   REGISTRY        default oci://ghcr.io/fernandoquinino-ntx   (collection -> <REGISTRY>/nkp-app-catalog/collection)
#   COLLECTION      default <REGISTRY>/nkp-app-catalog/collection
#   MAKE_PUBLIC     "true" to flip the pushed GHCR packages to public
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

TAG="${1:-${TAG:-}}"
[ -n "$TAG" ] || { echo "usage: $0 <tag>   e.g. v0.1.0" >&2; exit 2; }

[ -f .env.local ] && { set -a; . ./.env.local; set +a; }

NKP="${NKP:-nkp}"
command -v "$NKP" >/dev/null || { echo "nkp CLI not found (set NKP=<path>)" >&2; exit 1; }
: "${GHCR_USERNAME:?set GHCR_USERNAME (or .env.local)}"
: "${GHCR_PASSWORD:?set GHCR_PASSWORD (PAT with write:packages) }"

REGISTRY="${REGISTRY:-oci://ghcr.io/fernandoquinino-ntx}"
COLLECTION="${COLLECTION:-${REGISTRY}/nkp-app-catalog/collection}"

echo "== 1/4  validate =="
"$NKP" validate catalog-repository --repo-dir="$REPO_DIR"

echo "== 2/4  create catalog bundle (tag=${TAG}) =="
"$NKP" create catalog-bundle --collection-tag "$TAG"
TAR="$(ls -1t "${REPO_DIR}"/nkp-app-catalog*.tar 2>/dev/null | head -1 || true)"
[ -n "$TAR" ] || { echo "bundle tar not found in ${REPO_DIR}" >&2; exit 1; }
echo "   bundle: ${TAR}"

echo "== 3/4  registry login (ghcr.io) =="
if command -v helm >/dev/null; then
  echo "$GHCR_PASSWORD" | helm registry login ghcr.io -u "$GHCR_USERNAME" --password-stdin
else
  echo "$GHCR_PASSWORD" | docker login ghcr.io -u "$GHCR_USERNAME" --password-stdin
fi

echo "== 4/4  push bundle =="
"$NKP" push bundle "$TAR" \
  --to-registry "$REGISTRY" \
  --to-registry-username "$GHCR_USERNAME" \
  --to-registry-password "$GHCR_PASSWORD"

if [ "${MAKE_PUBLIC:-false}" = "true" ]; then
  echo "== GHCR package visibility (UI-only) =="
  GHCR_OWNER="${GHCR_USERNAME}" GHCR_PASSWORD="$GHCR_PASSWORD" "${REPO_DIR}/scripts/make-packages-public.sh" || \
    echo "   (could not list packages; set visibility manually in the GitHub package settings)"
fi

echo
echo "Collection URL : ${COLLECTION}:${TAG}"
echo "Register it in NKP with:"
echo "  ./add-catalog-to-cluster.sh --tag ${TAG} --url ${COLLECTION}"
