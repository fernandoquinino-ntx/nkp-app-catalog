#!/usr/bin/env bash
# make-packages-public.sh — GHCR package visibility is UI-ONLY.
#
# IMPORTANT: GitHub's REST API has NO endpoint to change a package's visibility
# (the /user|/orgs|/users packages endpoints support only GET, DELETE and /restore).
# Visibility must be set in the GitHub web UI, per package.
#
# This script lists this owner's container packages and prints the exact settings URL
# to open. Set each to "Public" so clusters can pull the catalog + charts anonymously.
#
# Usage: GHCR_OWNER=<login> GHCR_PASSWORD=<PAT> ./scripts/make-packages-public.sh
set -euo pipefail

API="https://api.github.com"
: "${GHCR_OWNER:?set GHCR_OWNER (github login/org)}"
: "${GHCR_PASSWORD:?set GHCR_PASSWORD (PAT with read:packages)}"

hdr=(-H "Authorization: token ${GHCR_PASSWORD}" -H "Accept: application/vnd.github+json")

owner_type="$(curl -s "${hdr[@]}" "$API/users/${GHCR_OWNER}" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("type",""))')"
if [ "$owner_type" = "Organization" ]; then
  LIST_URL="$API/orgs/${GHCR_OWNER}/packages?package_type=container&per_page=100"
  WEB_BASE="https://github.com/orgs/${GHCR_OWNER}/packages/container"
else
  LIST_URL="$API/user/packages?package_type=container&per_page=100"
  WEB_BASE="https://github.com/users/${GHCR_OWNER}/packages/container"
fi

echo ">> GHCR package visibility can only be changed in the GitHub UI (no REST API endpoint)."
echo ">> Open each package below and set Visibility = Public:"
echo

GHCR_OWNER="$GHCR_OWNER" WEB_BASE="$WEB_BASE" python3 - "$LIST_URL" "$GHCR_PASSWORD" <<'PY'
import sys, os, json, urllib.request, urllib.parse
list_url, pat = sys.argv[1], sys.argv[2]
req = urllib.request.Request(list_url, headers={
    "Authorization": "token " + pat, "Accept": "application/vnd.github+json"})
try:
    data = json.loads(urllib.request.urlopen(req, timeout=30).read())
except Exception as e:
    print("   (could not list packages:", e, ")"); raise SystemExit(0)
web = os.environ["WEB_BASE"]
for p in data:
    name = p["name"]; enc = urllib.parse.quote(name, safe="")
    print(f"   - {name}   (visibility = {p.get('visibility')})")
    print(f"       {web}/{enc}/settings")
PY

echo
echo "   Or: repo → Packages → select package → Package settings → Change visibility → Public."
