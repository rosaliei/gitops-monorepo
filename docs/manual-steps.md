# Manual steps: do everything by hand

Every step the pipelines automate, done by hand, in order. Follow it once and you will know
exactly what the automation in [automation-steps.md](automation-steps.md) does for you.

**Needs:** Docker, [kind](https://kind.sigs.k8s.io/), kubectl, Helm 3, Node 24. About 20 minutes.

| # | Step | Automated by |
|---|---|---|
| 1 | [Clone and look around](#1-clone-and-look-around) | - |
| 2 | [Create a local Kubernetes cluster](#2-create-a-local-kubernetes-cluster) | `make up` |
| 3 | [Run the unit tests](#3-run-the-unit-tests) | `_test.yaml` |
| 4 | [Build the images](#4-build-the-images) | `_build.yaml` |
| 5 | [Scan the image and the repo](#5-scan-the-image-and-the-repo) | `_build.yaml`, `security.yaml` |
| 6 | [Render and validate the Helm chart](#6-render-and-validate-the-helm-chart) | `scripts/validate.sh` |
| 7 | [Install the apps with Helm](#7-install-the-apps-with-helm) | ArgoCD |
| 8 | [Test the apps](#8-test-the-apps) | `scripts/e2e.sh` |
| 9 | [Give an app a secret](#9-give-an-app-a-secret) | External Secrets |
| 10 | [Upgrade and roll back with Helm](#10-upgrade-and-roll-back-with-helm) | ArgoCD + Git |
| 11 | [Install ArgoCD and hand over to Git](#11-install-argocd-and-hand-over-to-git) | `scripts/bootstrap.sh` |
| 12 | [Deploy by committing to Git](#12-deploy-by-committing-to-git) | `ci.yaml` → `deploy-dev` |
| 13 | [Promote qa → prod](#13-promote-qa--prod) | `promote.yaml` |
| 14 | [Prove that manual changes are blocked](#14-prove-that-manual-changes-are-blocked) | admission policy |
| 15 | [Look at metrics, alerts and dashboards](#15-look-at-metrics-alerts-and-dashboards) | kube-prometheus-stack |
| 16 | [Clean up](#16-clean-up) | `make down` |

---

## 1. Clone and look around
```bash
git clone https://github.com/rosaliei/gitops-monorepo.git && cd gitops-monorepo
ls apps/ charts/app/templates/ environments/*/     # 3 apps, 1 chart, 3 environments
cat environments/prod/orders-api.yaml              # everything prod needs to know about orders-api
```

## 2. Create a local Kubernetes cluster
```bash
kind create cluster --name gitops-demo --config infra/kind/cluster.yaml
kubectl get nodes
```

## 3. Run the unit tests
```bash
# Python (Docker, so you don't need Python 3.12 locally)
docker run --rm -v "$PWD/apps/orders-api:/src" -w /src python:3.12-slim \
  sh -c "pip install -q -r requirements-dev.txt && ruff check . && pytest -v"
# Node.js
(cd apps/inventory-svc && npm ci && npm test)
(cd apps/web-frontend && npm test)
```

## 4. Build the images
```bash
for app in orders-api inventory-svc web-frontend; do
  docker build -t local/$app:0.1.0 --build-arg APP_VERSION=0.1.0 apps/$app
done
docker images | grep local/
```

## 5. Scan the image and the repo
```bash
# the same gate as CI: fail on CRITICAL vulnerabilities that have a fix
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:0.74.0 \
  image --severity CRITICAL --ignore-unfixed --exit-code 1 local/orders-api:0.1.0
# no secrets anywhere in the Git history
docker run --rm -v "$PWD:/repo" ghcr.io/gitleaks/gitleaks:v8.30.1 git /repo --config /repo/.gitleaks.toml
```

## 6. Render and validate the Helm chart
```bash
helm lint charts/app -f environments/prod/orders-api.yaml
helm template orders-api charts/app -f environments/prod/orders-api.yaml    # exactly what prod gets
diff <(helm template x charts/app -f environments/qa/orders-api.yaml) \
     <(helm template x charts/app -f environments/prod/orders-api.yaml)     # qa vs prod
```

## 7. Install the apps with Helm
```bash
for app in orders-api inventory-svc web-frontend; do
  kind load docker-image local/$app:0.1.0 --name gitops-demo
  helm upgrade --install $app charts/app -n hands-on --create-namespace -f environments/dev/$app.yaml \
    --set environment=hands-on --set image.repository=local/$app --set image.tag=0.1.0 --set image.digest= \
    --set image.pullPolicy=Never --set secretEnv.enabled=false --set metrics.enabled=false \
    --set env.ORDERS_API_HOST=orders-api.hands-on.svc.cluster.local \
    --set env.INVENTORY_HOST=inventory-svc.hands-on.svc.cluster.local
done
kubectl -n hands-on get pods
```

## 8. Test the apps
```bash
kubectl -n hands-on port-forward svc/web-frontend 8081:80 &
curl localhost:8081/api/orders/info          # frontend -> orders-api
curl localhost:8081/api/inventory/items      # frontend -> inventory-svc
open http://localhost:8081                   # status page: which version runs here
```

## 9. Give an app a secret
```bash
kubectl -n hands-on create secret generic orders-api-secrets --from-literal=API_KEY=$(openssl rand -hex 16)
kubectl -n hands-on set env deploy/orders-api --from=secret/orders-api-secrets
curl localhost:8081/api/orders/info          # "secretConfigured": true (the value is never printed)
```

## 10. Upgrade and roll back with Helm
```bash
docker build -t local/orders-api:0.1.1 --build-arg APP_VERSION=0.1.1 apps/orders-api
kind load docker-image local/orders-api:0.1.1 --name gitops-demo
helm upgrade orders-api charts/app -n hands-on --reuse-values --set image.tag=0.1.1
helm history orders-api -n hands-on
helm rollback orders-api 1 -n hands-on       # back to 0.1.0
```
This works, but nothing records *why* it changed or *who* changed it. Steps 11-13 fix that with Git.

## 11. Install ArgoCD and hand over to Git
```bash
helm upgrade --install argocd argo-cd --repo https://argoproj.github.io/argo-helm --version 10.9.2 \
  -n argocd --create-namespace -f infra/kind/argocd-values.yaml --wait
kubectl apply -f argocd/bootstrap/root-app.yaml     # the ONLY manifest ever applied by hand
kubectl -n argocd get applications -w               # 4 platform apps + 9 service apps appear
```
Using a fork? Run `scripts/use-my-fork.sh <your-github-user>` first and push.

## 12. Deploy by committing to Git
```bash
scripts/set-image.sh dev orders-api 0.1.0     # edits environments/dev/orders-api.yaml
git diff
git commit -am "chore(dev): deploy orders-api 0.1.0" && git push
kubectl -n argocd get application orders-api-dev -w    # ArgoCD syncs within ~1 minute
```

## 13. Promote qa → prod
```bash
scripts/promote.sh orders-api qa prod         # copies qa's tag + digest into prod's file
git switch -c promote/orders-api && git commit -am "chore(prod): promote orders-api"
gh pr create --fill                           # review, merge = deploy to prod
```
Roll back the same way: `git revert <that commit>`.

## 14. Prove that manual changes are blocked
```bash
kubectl -n demo-prod set image deploy/orders-api orders-api=nginx:1.29
# Error: ... ValidatingAdmissionPolicy 'block-manual-changes' denied request:
#        Manual changes are blocked in GitOps namespaces ... Change the files in Git instead
```

## 15. Look at metrics, alerts and dashboards
```bash
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80 &      # admin / admin
open http://localhost:3000        # dashboards: "GitOps Delivery", "Services (RED)"
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090 &
open 'http://localhost:9090/graph?g0.expr=max%20by%20(namespace,job,version)(app_build_info)'   # what runs where
python3 scripts/pipeline_health.py            # DORA metrics from git history
```

## 16. Clean up
```bash
kind delete cluster --name gitops-demo
```
