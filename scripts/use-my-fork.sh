#!/usr/bin/env bash
# Point ArgoCD and image names at your fork:  scripts/use-my-fork.sh <github-user>
set -euo pipefail
cd "$(dirname "$0")/.."
new="${1:?github user or org (lowercase)}"
old=rosaliei
grep -rlE "github.com/$old/gitops-monorepo|ghcr.io/$old/" argocd environments platform docs README.md \
  | xargs sed -i.bak -E "s#github.com/$old/gitops-monorepo#github.com/$new/gitops-monorepo#g; s#ghcr.io/$old/#ghcr.io/$new/#g"
find . -name '*.bak' -delete
sed -i.bak "s/^old=.*/old=$new/" scripts/use-my-fork.sh && rm -f scripts/use-my-fork.sh.bak
echo "Now pointing at github.com/$new/gitops-monorepo. Commit and push, then run: make up"
