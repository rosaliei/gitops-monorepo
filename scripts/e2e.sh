#!/usr/bin/env bash
# End-to-end test on a throwaway kind cluster. CI runs exactly this script on every PR.
#   1. build the 3 images and load them into kind (no registry needed)
#   2. install the admission policies from platform/manifests/policies
#   3. helm install all 3 apps into a protected namespace and wait for rollout
#   4. smoke test through the frontend (frontend -> orders-api / inventory-svc)
#   5. prove the policies work: a manual change and a ':latest' image are both rejected,
#      and every real environment (dev/qa/prod) passes them
# KEEP_CLUSTER=1 keeps the cluster for poking around afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."

CLUSTER="${CLUSTER:-gitops-e2e}"
NS=demo-e2e
APPS=(orders-api inventory-svc web-frontend)
TAG=e2e

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31mFAIL: %s\033[0m\n' "$*"; exit 1; }
pass() { printf '\033[1;32mPASS: %s\033[0m\n' "$*"; }

cleanup() {
  if [ -n "${PF_PID:-}" ]; then kill "$PF_PID" 2>/dev/null || true; fi
  if [ "${KEEP_CLUSTER:-0}" != 1 ]; then kind delete cluster --name "$CLUSTER" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT

log "kind cluster '$CLUSTER'"
kind get clusters 2>/dev/null | grep -qx "$CLUSTER" || kind create cluster --name "$CLUSTER" --config infra/kind/cluster.yaml --wait 120s
kubectl config use-context "kind-$CLUSTER" >/dev/null

log "build + load images"
for app in "${APPS[@]}"; do
  docker build -q -t "local/$app:$TAG" --build-arg APP_VERSION=e2e --build-arg GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo local)" "apps/$app" >/dev/null
  kind load docker-image "local/$app:$TAG" --name "$CLUSTER" >/dev/null
  echo "loaded local/$app:$TAG"
done

log "admission policies"
kubectl apply -f platform/manifests/policies/
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "$NS" gitops.demo/protected=true --overwrite
kubectl create namespace policy-check --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace policy-check gitops.demo/protected=true --overwrite
sleep 5   # policies take a moment to become active

log "helm install (dev values, local images)"
for app in "${APPS[@]}"; do
  helm upgrade --install "$app" charts/app -n "$NS" -f "environments/dev/$app.yaml" \
    --set environment=e2e \
    --set image.repository="local/$app" --set image.tag="$TAG" --set image.digest="" --set image.pullPolicy=Never \
    --set secretEnv.enabled=false --set metrics.enabled=false \
    --set env.ORDERS_API_HOST="orders-api.$NS.svc.cluster.local" \
    --set env.INVENTORY_HOST="inventory-svc.$NS.svc.cluster.local" >/dev/null
  echo "installed $app"
done
for app in "${APPS[@]}"; do
  kubectl -n "$NS" rollout status "deploy/$app" --timeout=180s
done

log "smoke test through the frontend"
kubectl -n "$NS" port-forward svc/web-frontend 18080:80 >/dev/null 2>&1 &
PF_PID=$!
for _ in $(seq 1 30); do curl -sf localhost:18080/healthz >/dev/null && break; sleep 1; done
check() {  # check <path> <text that must appear>
  local body; body=$(curl -sf --retry 5 --retry-all-errors --retry-delay 2 "localhost:18080$1") || fail "GET $1"
  grep -q "$2" <<<"$body" || fail "GET $1 did not contain $2: $body"
  pass "GET $1 -> contains $2"
}
check /healthz '"ok"'
check /env.json '"e2e"'
check /api/orders/info '"orders-api"'
check /api/inventory/info '"inventory-svc"'
check /api/inventory/items 'sku-coffee'
check / 'GitOps Demo Shop'

log "policy: manual changes are rejected in a GitOps namespace"
if out=$(kubectl -n "$NS" set image deploy/orders-api orders-api=local/orders-api:hotfix 2>&1); then
  fail "manual change was allowed"
fi
grep -q "Manual changes are blocked" <<<"$out" || fail "unexpected error: $out"
pass "kubectl set image -> $(grep -o 'Manual changes are blocked[^(]*' <<<"$out")"

log "policy: ':latest' images are rejected"
if out=$(helm template bad charts/app --show-only templates/deployment.yaml \
      --set image.repository=nginx --set image.tag=latest \
    | kubectl apply --dry-run=server -n policy-check -f - 2>&1); then
  fail "':latest' image was allowed"
fi
grep -q "latest' is not allowed" <<<"$out" || fail "unexpected error: $out"
pass "image nginx:latest -> denied"

log "policy: every real environment passes"
for file in environments/*/*.yaml; do
  helm template "$(basename "$file" .yaml)" charts/app --show-only templates/deployment.yaml -f "$file" \
    | kubectl apply --dry-run=server -n policy-check -f - >/dev/null || fail "$file violates a policy"
  pass "$file"
done

log "all e2e checks passed"
