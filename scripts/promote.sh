#!/usr/bin/env bash
# Copy the exact image (tag + digest) that passed one environment into the next one.
# Nothing is rebuilt: prod runs the same bytes that were tested in qa.
#   usage: scripts/promote.sh <app> <from-env> <to-env>
#   e.g.   scripts/promote.sh orders-api qa prod
set -euo pipefail
cd "$(dirname "$0")/.."

app="${1:?app}"; from="${2:?from-env}"; to="${3:?to-env}"
case "$from->$to" in
  "dev->qa"|"qa->prod") ;;
  *) echo "promotion must go dev->qa or qa->prod (got $from->$to)" >&2; exit 1 ;;
esac

read_field() { grep -E "^  $1:" "environments/$2/$app.yaml" | sed -E 's/.*"(.*)"/\1/'; }
tag=$(read_field tag "$from")
digest=$(read_field digest "$from")

# Only released versions leave dev. CI builds (sha-xxxx) never reach qa/prod.
[[ "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "$from runs '$tag' - only release versions (x.y.z) can be promoted" >&2; exit 1; }
[ "$(read_field tag "$to")" != "$tag" ] || { echo "$to already runs $tag"; exit 0; }

scripts/set-image.sh "$to" "$app" "$tag" "$digest"
