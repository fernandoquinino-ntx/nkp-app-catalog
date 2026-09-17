#!/usr/bin/env bash
# catalog-workflow.sh — thin wrapper over the scripts in this repo.
#
#   ./catalog-workflow.sh add-app   --appname <n> --version <v> (--ocirepo oci://… | --helmrepo <r/c> --ocipush oci://…)
#   ./catalog-workflow.sh validate
#   ./catalog-workflow.sh build-push --tag v0.1.0
#   ./catalog-workflow.sh make-public
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sub="${1:-}"; shift || true

case "$sub" in
  add-app)
    exec "${REPO_DIR}/scripts/add-application.sh" "$@" ;;
  validate)
    exec "${REPO_DIR}/scripts/validate.sh" "$@" ;;
  build-push)
    tag=""; rest=()
    while [ $# -gt 0 ]; do case "$1" in --tag) tag="${2:?}"; shift 2 ;; *) rest+=("$1"); shift ;; esac; done
    exec "${REPO_DIR}/scripts/build-and-push.sh" "$tag" "${rest[@]}" ;;
  make-public)
    exec "${REPO_DIR}/scripts/make-packages-public.sh" "$@" ;;
  ""|-h|--help|help)
    sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//' ;;
  *)
    echo "unknown subcommand: $sub" >&2; exit 2 ;;
esac
