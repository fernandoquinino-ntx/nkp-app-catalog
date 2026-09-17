#!/usr/bin/env bash
# validate.sh — validate this catalog with the NKP CLI.
# Loads GHCR_USERNAME/GHCR_PASSWORD from .env.local if present (optional: OCI login).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

[ -f .env.local ] && { set -a; . ./.env.local; set +a; }

NKP="${NKP:-nkp}"
command -v "$NKP" >/dev/null || { echo "nkp CLI not found (set NKP=<path>)" >&2; exit 1; }

echo ">> nkp validate catalog-repository --repo-dir=$REPO_DIR"
"$NKP" validate catalog-repository --repo-dir="$REPO_DIR" "$@"
