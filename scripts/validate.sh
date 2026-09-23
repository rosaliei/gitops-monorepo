#!/usr/bin/env bash
# Static checks for every Kubernetes file in the repo. CI runs exactly this script.
#   1. helm lint      - chart is well formed for every environment
#   2. helm template  - every environment renders (output kept in .out/rendered for review)
#   3. kubeconform    - every rendered object matches the Kubernetes / CRD schema
set -euo pipefail
cd "$(dirname "$0")/.."

KUBE_VERSION="${KUBE_VERSION:-1.34.0}"
KUBECONFORM="${KUBECONFORM:-$(command -v kubeconform || echo .out/bin/kubeconform)}"
OUT=.out/rendered
rm -rf "$OUT" && mkdir -p "$OUT"

echo "==> helm lint + template (chart defaults with every feature on)"
helm lint charts/app --strict -f charts/app/ci/all-features-values.yaml
helm template ci charts/app -f charts/app/ci/all-features-values.yaml > "$OUT/ci-all-features.yaml"

for file in environments/*/*.yaml; do
  env=$(basename "$(dirname "$file")")
  app=$(basename "$file" .yaml)
  echo "==> $env/$app"
  helm lint charts/app --strict --quiet -f "$file"
  helm template "$app" charts/app --namespace "demo-$env" -f "$file" > "$OUT/$env-$app.yaml"
done

echo "==> kubeconform (Kubernetes $KUBE_VERSION + CRDs catalog)"
"$KUBECONFORM" -strict -summary -kubernetes-version "$KUBE_VERSION" \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  "$OUT" argocd platform/manifests

echo "All manifests are valid."
