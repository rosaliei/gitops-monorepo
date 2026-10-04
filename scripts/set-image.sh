#!/usr/bin/env bash
# Point one app in one environment at an image. In GitOps, committing this change IS the deployment.
#   usage: scripts/set-image.sh <env> <app> <tag> [digest]
#   e.g.   scripts/set-image.sh dev orders-api sha-1a2b3c4 sha256:...
# CI uses this script for dev deploys and promotions, so doing it by hand is exactly the same.
set -euo pipefail
cd "$(dirname "$0")/.."

env="${1:?env}"; app="${2:?app}"; tag="${3:?tag}"; digest="${4:-}"
file="environments/$env/$app.yaml"
[ -f "$file" ] || { echo "no such file: $file" >&2; exit 1; }
[ "$tag" != latest ] || { echo "refusing to deploy ':latest'" >&2; exit 1; }
[ -z "$digest" ] || [[ "$digest" =~ ^sha256:[a-f0-9]{64}$ ]] || { echo "bad digest: $digest" >&2; exit 1; }

sed -i.bak -E "s|^  tag: .*|  tag: \"$tag\"|; s|^  digest: .*|  digest: \"$digest\"|" "$file" && rm -f "$file.bak"
echo "$file -> $tag ${digest:+@ ${digest:0:19}...}"
