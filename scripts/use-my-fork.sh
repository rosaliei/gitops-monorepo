#!/usr/bin/env bash
# Point ArgoCD, image names and the app repo at your forks:  scripts/use-my-fork.sh <github-user>
# (fork both repos: gitops-monorepo and gitops-apps)
set -euo pipefail
cd "$(dirname "$0")/.."
new="${1:?github user or org (lowercase)}"
old=rosaliei
grep -rlE "github.com/$old/gitops-(monorepo|apps)|ghcr.io/$old/" argocd environments platform scripts docs README.md \
  | xargs sed -i.bak -E "s#github.com/$old/gitops-(monorepo|apps)#github.com/$new/gitops-\1#g; s#ghcr.io/$old/#ghcr.io/$new/#g"
find . -name '*.bak' -delete
sed -i.bak "s/^old=.*/old=$new/" scripts/use-my-fork.sh && rm -f scripts/use-my-fork.sh.bak
echo "Now pointing at github.com/$new/gitops-monorepo. Commit and push, then run: make up"
