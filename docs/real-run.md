# Real run: every step, with screenshots

This is the [manual walkthrough](manual-steps.md) performed for real on 3 October 2026, with a
screenshot of what was typed and what happened at each step. Terminal screenshots are the actual
command output (long output trimmed with `...`). UI screenshots are the real ArgoCD, GitHub and
Prometheus pages; the **red numbered boxes** mark what was clicked next.

> Recorded before the repo was split into `gitops-apps/` and `gitops-config/`; paths in the screenshots show the old layout
> (`apps/`, `environments/`), but every step works the same today.

Release `0.2.0` was actually shipped during this run: release PR → CI → dev → qa → approval → prod.

| # | Step | # | Step |
|---|---|---|---|
| 1 | [Clone](#1-clone) | 9 | [Secret](#9-give-an-app-a-secret) |
| 2 | [Cluster](#2-create-a-kubernetes-cluster) | 10 | [Helm upgrade + rollback](#10-upgrade-and-roll-back-with-helm) |
| 3 | [Unit tests](#3-unit-tests) | 11 | [ArgoCD](#11-argocd-everything-from-git) |
| 4 | [Build](#4-build-the-images) | 12 | [Release → dev → qa through Git](#12-release--dev--qa-everything-through-git) |
| 5 | [Scan](#5-scan) | 13 | [Promote to prod (by hand + with approval)](#13-promote-qa--prod) |
| 6 | [Helm render](#6-render-and-validate-the-chart) | 14 | [Manual changes blocked](#14-manual-changes-are-blocked) |
| 7 | [Helm install](#7-install-with-helm) | 15 | [Metrics + DORA](#15-metrics-dashboards-dora) |
| 8 | [Test the apps](#8-test-the-apps) | 16 | [Clean up](#16-clean-up) |

---

## 1. Clone
![clone](real-run/01-clone.jpg)

## 2. Create a Kubernetes cluster
A throwaway `walkthrough` cluster for steps 2-10 (the GitOps platform runs in `gitops-demo`).

![kind create](real-run/02-kind-create.jpg)
![node ready](real-run/02-node-ready.jpg)

## 3. Unit tests
6 Python + 5 Node + 3 frontend tests, ruff clean.

![tests](real-run/03-unit-tests.jpg)

## 4. Build the images
![build](real-run/04-build-images.jpg)

## 5. Scan
Trivy gate (0 fixable CRITICAL) and Gitleaks over the whole Git history (no leaks).

![scan](real-run/05-trivy-gitleaks.jpg)

## 6. Render and validate the chart
Note the qa/prod diff: qa pins a digest, prod uses an HPA instead of fixed replicas, different log level and limits.

![helm](real-run/06-helm-lint-template-diff.jpg)

## 7. Install with Helm
![install](real-run/07-helm-install.jpg)

## 8. Test the apps
![curl](real-run/08-curl.jpg)
![shop](real-run/08-shop-page.jpg)

## 9. Give an app a secret
![secret](real-run/09-secret.jpg)

## 10. Upgrade and roll back with Helm
Works, but nothing in Git records it. Steps 11+ move the history into Git.

![helm upgrade rollback](real-run/10-helm-upgrade-rollback.jpg)

## 11. ArgoCD: everything from Git
Log in, 14 applications Synced + Healthy, and the app of apps: `root` → platform apps, AppProjects, and the
ApplicationSet that fans out to 9 service apps.

![login](real-run/11-argocd-login.jpg)
![applications](real-run/11-argocd-applications.jpg)
![root](real-run/11-argocd-root-app-of-apps.jpg)

## 12. Release → dev → qa, everything through Git

**12.1-12.2** release-please keeps a release PR open: next version + CHANGELOG for every app.

![release pr](real-run/12-1-release-pr.jpg)
![version.txt](real-run/12-2-release-pr-version-txt.jpg)

**12.3-12.6** Merge it → CI/CD, Release and Security start. CI builds once, signs, deploys dev and opens the qa PR.
release-please tags `*-v0.2.0` and publishes GitHub Releases.

![merge release](real-run/12-3-merge-release.jpg)
![actions](real-run/12-4-actions-started.jpg)
![run graph](real-run/12-5-ci-run-graph.jpg)
![releases](real-run/12-6-github-releases.jpg)

**12.7-12.9** The qa PR is opened **by CI**. Its digest `sha256:f9d76136…` is the exact build dev already runs. Merge = deploy qa.

![qa pr](real-run/12-7-qa-pr-by-ci.jpg)
![qa pr files](real-run/12-8-qa-pr-same-digest.jpg)
![merge qa](real-run/12-9-merge-qa-pr.jpg)

**12.10-12.11** ArgoCD had already synced qa (auto-sync); History shows the bot's commit, initiated by the automated sync policy, deployed in 3 s.

![qa refresh](real-run/12-10-argocd-qa-refresh.jpg)
![qa history](real-run/12-11-argocd-qa-history.jpg)

**12.12-12.14** Deploy by hand = edit one file + `git push`. Only the tag line changes: same digest, same bytes.
ArgoCD synced it within a minute (Deployment rev 4).

![deploy dev](real-run/12-12-deploy-dev-by-hand.jpg)
![dev synced](real-run/12-13-argocd-dev-synced.jpg)
![dev history](real-run/12-14-argocd-dev-history.jpg)

## 13. Promote qa → prod

**By hand** (`orders-api`): `promote.sh` copies qa's tag + digest, then a PR with all checks green.

![promote.sh](real-run/13-1-promote-sh-and-pr.jpg)
![prod pr](real-run/13-2-prod-pr-checks.jpg)
![prod pr diff](real-run/13-3-prod-pr-diff.jpg)

**With the workflow** (`inventory-svc`): *Actions → Promote to production* stops at the **required reviewer**, then opens the PR.

![waiting](real-run/13-4-promote-workflow-waiting-approval.jpg)
![approve](real-run/13-5-approve.jpg)
![done](real-run/13-6-promote-workflow-done.jpg)

**Merge = deploy prod.** ArgoCD rolls prod (rev 2), and prod now runs the digests qa tested.

![merge prod](real-run/13-7-merge-prod-prs.jpg)
![prod tree](real-run/13-8-argocd-prod-tree.jpg)
![prod history](real-run/13-9-argocd-prod-history.jpg)
![prod running](real-run/13-10-prod-running-0.2.0.jpg)
![shop prod](real-run/13-11-shop-prod.jpg)

## 14. Manual changes are blocked
`set image`, `scale` and `delete` are all denied in a GitOps namespace, even for cluster-admin.

> **Found during this run:** `kubectl scale` was first *allowed*, because it goes through the
> `deployments/scale` subresource. Fixed in commit `2807695` (policy now matches it, e2e asserts it).

![denied](real-run/14-manual-changes-denied.jpg)

## 15. Metrics, dashboards, DORA
Grafana dashboards are provisioned from Git; Prometheus shows which version runs where, request rates,
and ArgoCD app state; DORA metrics come straight from `git log` (lead time release → prod: 0.5 h).

![grafana api + dora](real-run/15-1-dashboards-and-dora.jpg)
![what runs where](real-run/15-2-prometheus-what-runs-where.jpg)
![request rate](real-run/15-3-prometheus-request-rate.jpg)
![argocd apps](real-run/15-4-prometheus-argocd-apps.jpg)

## 16. Clean up
Deletes the throwaway cluster; `gitops-demo` keeps running.

![cleanup](real-run/16-cleanup.jpg)
