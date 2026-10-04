# Every target is a shortcut for commands shown step by step in docs/manual-steps.md.
# This is the GitOps repo (how and where apps run). The app code is in github.com/rosaliei/gitops-apps.
APPS     := orders-api inventory-svc web-frontend
APP_REPO ?= https://github.com/rosaliei/gitops-apps.git
APPS_DIR ?= ../gitops-apps
CLUSTER ?= gitops-demo
ENV     ?= dev

.PHONY: help app-repo lint e2e up down status ui-argocd ui-grafana ui-shop hands-on promote health

help: ## show targets
	@grep -E '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-12s %s\n", $$1, $$2}'

## ---- CI, locally ----
app-repo: ## clone the app repo next to this one (../gitops-apps), needed by e2e and hands-on
	@[ -d $(APPS_DIR) ] || git clone -q $(APP_REPO) $(APPS_DIR)

lint: ## helm lint + render every environment + schema validation
	scripts/validate.sh

e2e: app-repo ## throwaway kind cluster: build the apps, deploy them with this chart, smoke test, prove the policies work
	APPS_DIR=$(abspath $(APPS_DIR)) scripts/e2e.sh

## ---- local GitOps platform ----
up: ## kind + ArgoCD + app-of-apps (ArgoCD installs everything else from Git)
	CLUSTER=$(CLUSTER) scripts/bootstrap.sh

down: ## delete the local cluster
	kind delete cluster --name $(CLUSTER)

status: ## what ArgoCD is running
	kubectl -n argocd get applications -o custom-columns='APP:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,IMAGES:.status.summary.images'

ui-argocd: ## ArgoCD UI on http://localhost:8085
	kubectl -n argocd port-forward svc/argocd-server 8085:80

ui-grafana: ## Grafana on http://localhost:3000 (admin/admin)
	kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80

ui-shop: ## the demo shop of ENV (dev|qa|prod) on http://localhost:8081
	kubectl -n demo-$(ENV) port-forward svc/web-frontend 8081:80

## ---- by hand (no ArgoCD) ----
hands-on: app-repo ## build, load and helm-install all apps into namespace "hands-on"
	kind get clusters | grep -qx $(CLUSTER) || kind create cluster --name $(CLUSTER) --config infra/kind/cluster.yaml
	@for app in $(APPS); do \
	  docker build -q -t local/$$app:0.1.0 --build-arg APP_VERSION=0.1.0 $(APPS_DIR)/$$app >/dev/null && \
	  kind load docker-image local/$$app:0.1.0 --name $(CLUSTER) >/dev/null && \
	  helm upgrade --install $$app charts/app -n hands-on --create-namespace -f environments/dev/$$app.yaml \
	    --set environment=hands-on --set image.repository=local/$$app --set image.tag=0.1.0 --set image.digest= \
	    --set image.pullPolicy=Never --set secretEnv.enabled=false --set metrics.enabled=false \
	    --set env.ORDERS_API_HOST=orders-api.hands-on.svc.cluster.local \
	    --set env.INVENTORY_HOST=inventory-svc.hands-on.svc.cluster.local && \
	  echo "installed $$app"; \
	done

promote: ## copy the image qa runs into prod (APP=orders-api), then commit + open a PR
	scripts/promote.sh $(APP) qa prod

health: ## delivery metrics (DORA) from git history
	python3 scripts/pipeline_health.py
