# Every target is a shortcut for commands shown step by step in docs/manual-steps.md.
# gitops-apps/   = application code (app team)     gitops-config/ = how and where it runs (devops team)
APPS    := orders-api inventory-svc web-frontend
CLUSTER ?= gitops-demo
ENV     ?= dev

.PHONY: help test lint e2e up down status ui-argocd ui-grafana ui-shop hands-on promote health

help: ## show targets
	@grep -E '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-12s %s\n", $$1, $$2}'

## ---- CI, locally ----
test: ## unit tests for all apps (Python runs in Docker, so only Docker + Node are needed)
	docker run --rm -v "$(CURDIR)/gitops-apps/orders-api:/src" -w /src python:3.12-slim \
	  sh -c "pip install -q -r requirements-dev.txt && ruff check . && pytest -q"
	cd gitops-apps/inventory-svc && npm ci --silent && npm run lint && npm test
	cd gitops-apps/web-frontend && npm run lint && npm test

lint: ## helm lint + render every environment + schema validation
	gitops-config/scripts/validate.sh

e2e: ## throwaway kind cluster: deploy all apps, smoke test, prove the policies work
	gitops-config/scripts/e2e.sh

## ---- local GitOps platform ----
up: ## kind + ArgoCD + app-of-apps (ArgoCD installs everything else from Git)
	CLUSTER=$(CLUSTER) gitops-config/scripts/bootstrap.sh

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
hands-on: ## build, load and helm-install all apps into namespace "hands-on"
	kind get clusters | grep -qx $(CLUSTER) || kind create cluster --name $(CLUSTER) --config gitops-config/infra/kind/cluster.yaml
	@for app in $(APPS); do \
	  docker build -q -t local/$$app:0.1.0 --build-arg APP_VERSION=0.1.0 gitops-apps/$$app >/dev/null && \
	  kind load docker-image local/$$app:0.1.0 --name $(CLUSTER) >/dev/null && \
	  helm upgrade --install $$app gitops-config/charts/app -n hands-on --create-namespace -f gitops-config/environments/dev/$$app.yaml \
	    --set environment=hands-on --set image.repository=local/$$app --set image.tag=0.1.0 --set image.digest= \
	    --set image.pullPolicy=Never --set secretEnv.enabled=false --set metrics.enabled=false \
	    --set env.ORDERS_API_HOST=orders-api.hands-on.svc.cluster.local \
	    --set env.INVENTORY_HOST=inventory-svc.hands-on.svc.cluster.local && \
	  echo "installed $$app"; \
	done

promote: ## copy the image qa runs into prod (APP=orders-api), then commit + open a PR
	gitops-config/scripts/promote.sh $(APP) qa prod

health: ## delivery metrics (DORA) from git history
	python3 gitops-config/scripts/pipeline_health.py
