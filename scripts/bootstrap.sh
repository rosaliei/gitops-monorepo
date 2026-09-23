#!/usr/bin/env bash
# Local GitOps platform in one command: kind cluster + ArgoCD + the root "app of apps".
# From then on ArgoCD installs everything else from Git (monitoring, secrets, policies, apps).
set -euo pipefail
cd "$(dirname "$0")/.."

CLUSTER="${CLUSTER:-gitops-demo}"
ARGOCD_CHART_VERSION=10.9.2

kind get clusters 2>/dev/null | grep -qx "$CLUSTER" || kind create cluster --name "$CLUSTER" --config infra/kind/cluster.yaml --wait 120s
kubectl config use-context "kind-$CLUSTER" >/dev/null

echo "==> installing ArgoCD $ARGOCD_CHART_VERSION"
helm upgrade --install argocd argo-cd --repo https://argoproj.github.io/argo-helm --version "$ARGOCD_CHART_VERSION" \
  --namespace argocd --create-namespace -f infra/kind/argocd-values.yaml --wait --timeout 10m

echo "==> handing over to GitOps"
kubectl apply -f argocd/bootstrap/root-app.yaml

cat <<MSG

ArgoCD is installing the rest from Git. Watch it:
  kubectl -n argocd get applications -w

ArgoCD UI:  make ui-argocd   -> http://localhost:8080  (user: admin)
  password: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
Grafana:    make ui-grafana  -> http://localhost:3000  (admin / admin)
Shop (dev): make ui-shop ENV=dev -> http://localhost:8081
MSG
