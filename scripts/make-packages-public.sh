#!/usr/bin/env bash
# make-packages-public.sh — set this owner's GHCR container packages to public.
# Container packages are PRIVATE by default; a cluster must be able to pull the catalog + charts.
# Needs a token with write:packages (delete:packages helps for some visibility changes).
#
# Usage: GHCR_OWNER=<login> GHCR_PASSWORD=<pat> ./scripts/make-packages-public.sh [name-substring]
set -euo pipefail

API="https://api.github.com"
: "${GHCR_OWNER:?set GHCR_OWNER (github login/org)}"
: "${GHCR_PASSWORD:?set GHCR_PASSWORD (PAT)}"
FILTER="${1:-}"

hdr=(-H "Authorization: token ${GHCR_PASSWORD}" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")

# user vs org endpoint
owner_type="$(curl -s "${hdr[@]}" "$API/users/${GHCR_OWNER}" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("type",""))')"
if [ "$owner_type" = "Organization" ]; then
  LIST="$API/orgs/${GHCR_OWNER}/packages?package_type=container&per_page=100"
  PATCH_BASE="$API/orgs/${GHCR_OWNER}/packages/container"
else
  LIST="$API/user/packages?package_type=container&per_page=100"
  PATCH_BASE="$API/user/packages/container"
fi

echo ">> listing container packages for ${GHCR_OWNER} (${owner_type:-User})"
names="$(curl -s "${hdr[@]}" "$LIST" | python3 -c 'import sys,json
d=json.load(sys.stdin)
[print(p["name"]) for p in d if isinstance(d,list)]')"
[ -n "$names" ] || { echo "   (no packages found)"; exit 0; }

rc=0
while IFS= read -r name; do
  [ -n "$name" ] || continue
  [ -n "$FILTER" ] && case "$name" in *"$FILTER"*) ;; *) continue ;; esac
  enc="$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=""))' "$name")"
  code="$(curl -s -o /dev/null -w '%{http_code}' -X PATCH "${hdr[@]}" "$PATCH_BASE/$enc" -d '{"visibility":"public"}')"
  case "$code" in
    200|204) echo "   public : $name" ;;
    *)       echo "   HTTP $code : $name  (set manually in GitHub → Packages → settings)"; rc=1 ;;
  esac
done <<< "$names"

exit $rc
