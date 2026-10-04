# Automation steps: what the pipelines do

The same journey as [manual-steps.md](manual-steps.md), done by GitHub Actions and ArgoCD.
The numbers match the walkthrough diagram:

![Walkthrough](diagrams/2-walkthrough.svg)

Two repos take part: the **app repo** ([gitops-apps](https://github.com/rosaliei/gitops-apps), code → images) and
**this GitOps repo** (what runs where). The *Repo* column says where each step happens.

| # | You do | Automation does | Repo | File |
|---|---|---|---|---|
| 1 | open a PR | app change: tests, e2e, build + scan · config change: validation + e2e | app · GitOps | [`ci.yaml`](https://github.com/rosaliei/gitops-apps/blob/main/.github/workflows/ci.yaml) · [`ci.yaml`](../.github/workflows/ci.yaml) |
| 2 | nothing | checks the PR title (Conventional Commits) | both | [`pr-title.yaml`](../.github/workflows/pr-title.yaml) |
| 3 | merge the PR | builds once, pushes, signs | app | [`_build.yaml`](https://github.com/rosaliei/gitops-apps/blob/main/.github/workflows/_build.yaml) |
| 4 | nothing | deploys to **dev** by committing to this repo (deploy key) | app → GitOps | `ci.yaml` → `deploy-dev` |
| 5 | merge the release PR | versions the app, pushes a `promote/qa-*` branch here, which opens the **qa** PR | app → GitOps | [`release-please.yaml`](https://github.com/rosaliei/gitops-apps/blob/main/.github/workflows/release-please.yaml) · [`promotion-pr.yaml`](../.github/workflows/promotion-pr.yaml) |
| 6 | merge the qa PR | ArgoCD deploys **qa** | GitOps | [`30-demo-apps.yaml`](../argocd/apps/30-demo-apps.yaml) |
| 7 | run *Promote to production*, approve, merge | opens the **prod** PR with the same digest | GitOps | [`promote.yaml`](../.github/workflows/promote.yaml) |
| 8 | nothing | ArgoCD syncs, self-heals, notifies | GitOps | [`argocd/`](../argocd) |
| 9 | run *Promote* with an older version | rollback through the same path | GitOps | `promote.yaml` |
| 10 | read the results | pipeline monitoring + DORA metrics | GitOps | [`pipeline-health.yaml`](../.github/workflows/pipeline-health.yaml) |
| 11 | nothing | weekly security scans, dependency PRs | both | [`security.yaml`](../.github/workflows/security.yaml), [`dependabot.yml`](../.github/dependabot.yml) |
| 12 | change `infra/eks` | Terraform fmt + validate | GitOps | [`terraform.yaml`](../.github/workflows/terraform.yaml) |

---

## 1. Open a pull request → PR checks
**Trigger:** any PR. **Workflows:** in the app repo [`ci.yaml`](https://github.com/rosaliei/gitops-apps/blob/main/.github/workflows/ci.yaml) (code change); in this repo [`ci.yaml`](../.github/workflows/ci.yaml) (config change). Plus `security.yaml`, `lint-workflows.yaml` in both.

| Job | What it does | Fails when |
|---|---|---|
| detect changes | `dorny/paths-filter` → list of changed apps | - |
| test (per app) *(app repo)* | reusable [`_test.yaml`](https://github.com/rosaliei/gitops-apps/blob/main/.github/workflows/_test.yaml): ruff + pytest, or node --test | a test fails |
| validate manifests *(GitOps repo)* | [`scripts/validate.sh`](../scripts/validate.sh): helm lint + template for every env + kubeconform | a chart or ArgoCD file is invalid |
| e2e (kind) *(both)* | [`scripts/e2e.sh`](../scripts/e2e.sh): real cluster, the apps built from the app repo + this repo's chart, smoke test, policy tests | anything doesn't start, or a policy doesn't block |
| build (per app) *(app repo)* | build + Trivy gate, **nothing is published** | fixable CRITICAL CVE |
| gitleaks / trivy | secrets in history; dependency + misconfig report | a secret is found |

**You see:** green checks on the PR, and the rendered manifests as a downloadable artifact.

## 2. PR title check
`feat: …` / `fix: …` / `chore: …` are required, because with squash-merge the title becomes the commit
message, and step 5 turns it into a version number.

## 3. Merge → build once, push, sign (app repo)
The same checks run again, then for each changed app:
1. multi-arch image (`linux/amd64`, `linux/arm64`) → `ghcr.io/rosaliei/<app>:sha-<commit>`
2. SBOM + provenance attestations
3. keyless **cosign** signature on the digest
4. if `<app>/version.txt` (app repo) holds a version that is not in the registry yet, the **same build** is also tagged `x.y.z`

**You see:** a summary table on the run: app, tag, release, digest, and the Trivy output.

## 4. Deploy to dev (automatic, app repo → this repo)
The app repo's `deploy-dev` job checks out **this** repo with a **deploy key** (secret `GITOPS_DEPLOY_KEY`: SSH,
write access to this one repo, no API access), runs `scripts/set-image.sh dev <app> <tag> <digest>` and pushes:
```
chore(dev): deploy orders-api:sha-4e9a42f
```
This repo's CI validates the commit, and ArgoCD syncs `demo-dev` within a minute. **CI never talks to the cluster.**

## 5. Release (release-please, app repo)
release-please keeps a **release PR** open with the next version and CHANGELOG for each app
(`fix` → patch, `feat` → minor). Merging it tags `orders-api-v0.2.0` and bumps `version.txt`.
Step 3 then publishes `0.2.0`, and `deploy-dev` pushes a branch `promote/qa-<sha>` to this repo with the qa change.
A deploy key can push but cannot open PRs, so this repo's [`promotion-pr.yaml`](../.github/workflows/promotion-pr.yaml)
turns the branch into the PR:
```
chore(qa): promote orders-api:0.2.0      environments/qa/orders-api.yaml  tag + digest
```

## 6. Merge the qa PR → qa deploys
ArgoCD syncs `demo-qa`. qa now runs **the exact digest that dev tested**.

## 7. Promote to production (approval)
**Actions → Promote to production → Run workflow** (app, version empty):
1. `plan` reads qa's tag + digest, checks the image exists in GHCR and the digest matches
2. `production` job **waits for a required reviewer** (GitHub Environment `production`)
3. it opens `chore(prod): promote orders-api 0.1.0 -> 0.2.0` → merging it = the deploy

## 8. ArgoCD keeps the cluster equal to Git
- one **ApplicationSet** → 9 Applications (3 apps × 3 envs), auto-sync with `prune` + `selfHeal`
- **admission policies** reject `:latest`, root containers and missing limits, and block manual edits in `demo-*`
- **ArgoCD Notifications** → Slack: *deployed*, *degraded*, *sync failed*

## 9. Rollback
Run *Promote to production* with `version: 0.1.0`. The plan labels it `rollback`, and it takes the
same approval → PR → merge path. The DORA report counts it as a failed change.

## 10. Monitoring the pipelines
| Signal | Where |
|---|---|
| per-run summary tables (apps, tests, e2e, digest, scan, deploy) | each Actions run |
| pipeline result → Slack (secret `SLACK_WEBHOOK_URL`) | app repo `ci.yaml` → `report` |
| deploy events → Slack | ArgoCD Notifications |
| **what version runs where**, sync/health, syncs per day | Grafana → *GitOps Delivery* |
| deploy frequency, lead time, change failure rate, CI success rate | *Pipeline health* workflow (daily) |

## 11. Security on autopilot
- weekly Gitleaks + Trivy scans, even when no code changed (new CVEs appear anyway)
- Dependabot PRs for pip, npm, base images (app repo) and actions (both repos), all going through step 1
- workflows linted with actionlint + shellcheck

## 12. Infrastructure
Changes to `infra/eks` run `terraform fmt -check`, `init` and `validate`. `apply` is a deliberate,
reviewed step. See [eks-and-rancher.md](eks-and-rancher.md).
