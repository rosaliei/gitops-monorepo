# Interview guide - design decisions and how to talk about them

Short answers to the questions this repo usually triggers. Each links to where it lives.

### "Walk me through what happens when a developer merges a PR."
1. PR: unit tests for the changed apps, `helm lint` + render + schema check for every
   environment, e2e on a throwaway kind cluster, image build + Trivy scan. The PR title is checked for
   Conventional Commits. ([apps-ci.yaml](../.github/workflows/apps-ci.yaml))
2. Merge: the same checks run again, then the image is pushed (amd64 + arm64), signed with cosign
   (keyless), and gets an SBOM + provenance.
3. The pipeline **commits** the new tag + digest to `gitops-config/environments/dev/<app>.yaml`. That commit is the deployment.
4. ArgoCD sees the commit and syncs `demo-dev`. The pipeline never touches the cluster.

### "Why doesn't CI run `kubectl apply` / `helm upgrade`?"
- The cluster does not trust CI: no cluster credentials in GitHub. ArgoCD **pulls** from inside the cluster.
- Git is the audit log: who deployed what, when, approved by whom = `git log gitops-config/environments/`.
- Rollback = `git revert`. Drift is detected and healed automatically.

### "Where do the Helm charts live? Why separate app code from config?"
Two owners, two folders (in a company: two repos). `gitops-apps/` belongs to developers: code, tests, Dockerfiles.
`gitops-config/` belongs to devops: the **shared Helm chart**, the environment values, ArgoCD and the platform.
The chart lives with the config because it is shared by every app and describes *how* apps run, not *what* they do;
developers never need to learn Helm. ArgoCD reads only `gitops-config/`, and the only bridge is the app pipeline
committing a new image tag there. If an app ever needed its own special chart, I would publish it to an OCI registry
and pin its version in `gitops-config/`.

### "Why environment folders instead of environment branches?"
With a branch per environment, the branches drift and promotion becomes a merge with conflicts.
Folders on one branch make the difference between environments a plain diff
(`diff gitops-config/environments/qa gitops-config/environments/prod`), and promotion is a one-line change to a file.

### "How do you make sure prod runs exactly what you tested?"
**Build once, promote the digest.** The image is built one time. qa and prod receive the same
`tag + sha256 digest` ([gitops-config/scripts/promote.sh](../gitops-config/scripts/promote.sh)). The chart renders
`repo:tag@sha256:...`, so even if someone re-pushed the tag, the cluster would run the original bytes.
The promote workflow also checks that the tag and digest still match in the registry.

### "How does versioning work in a monorepo?"
release-please, per app: Conventional Commits (`feat:` → minor, `fix:` → patch) → a release PR
with the next version + CHANGELOG. Merging it tags `<app>-v<x.y.z>`. CI notices that version is not
in the registry yet, publishes it and opens the qa PR. Dev builds are `sha-<commit>` and never leave dev.

### "How do you control production?"
- The promote workflow runs in the GitHub Environment `production`, which has required reviewers,
  so a person approves it. Then it opens a PR, and merging that PR is the deploy. Two gates, both recorded.
- The ArgoCD `demo` AppProject allows only this repo, only `demo-*` namespaces and only 5 resource kinds.
- Admission policies reject `:latest`, root containers, privileged containers, missing memory limits,
  and any manual change in GitOps namespaces.

### "ArgoCD self-heal is on. Why do you need the manual-change policy?"
With server-side apply, Kubernetes tracks field ownership. Self-heal only reverts fields ArgoCD owns.
An env var added through Rancher or `kubectl edit` is owned by another manager, so ArgoCD ignores it
and it stays. Blocking at admission (built-in ValidatingAdmissionPolicy + CEL, no extra controller)
stops the drift from happening at all. ([policy](../gitops-config/platform/manifests/policies/block-manual-changes.yaml))

### "Where are the secrets?"
Not in Git, not in GitHub Secrets. GitHub Secrets only hold what the **pipeline** needs (the
registry token is the built-in `GITHUB_TOKEN`; Slack is optional). App secrets live in a secret store.
External Secrets Operator syncs them into Kubernetes, and the chart only references the key name.
Locally the store is a `fake` provider. On EKS it is AWS Secrets Manager with Pod Identity. The apps
don't change between the two.
(Why not Sealed Secrets: the encrypted files are tied to one cluster's key, so a fresh demo
cluster could not decrypt them.)

### "How do you monitor the pipeline itself?"
- Every run writes a summary (what was built, digest, scan result, what was deployed).
- Optional Slack messages from the pipeline, and from ArgoCD Notifications (deployed / degraded / sync failed).
- Grafana *GitOps Delivery* dashboard: sync/health of every app, **which version runs where**, syncs per day.
- A daily *Pipeline health* workflow computes DORA-style metrics from Git (deploy frequency, lead
  time, change failure rate) + CI success rate.

### "What are your SLOs?"
99% of requests succeed over 30 days. Alerting uses multi-window burn rate (1h and 5m at 14.4x),
so it pages on real budget burn and clears quickly after a fix. Every alert has a runbook.

### "What is p99, and why not just the average?"
p99 is the latency that 99 out of 100 requests beat, so it describes the slowest 1%: the *tail*.
Averages hide it: if 2 of every 100 requests take 5 s and the rest 1 ms, the average is about 100 ms but p99 is 5 s.
Here, Prometheus recording rules compute p50, p95 and p99 from the request-duration **histogram**
(`histogram_quantile` over the buckets). The values are estimates, interpolated inside a bucket, so bucket
boundaries matter. Alerts fire on p95 > 500 ms and p99 > 1 s for 10 minutes, and the rules have a promtool
unit test proving the p99 alert fires on a 2% slow tail while p95 stays quiet.
([alerts.yaml](../gitops-config/platform/manifests/monitoring/alerts.yaml), [test](../gitops-config/platform/tests/latency-rules.test.yaml))

### "What would you add for a real company?"
Webhook instead of polling, ArgoCD SSO + RBAC, image signature verification at admission
(policy-controller / Kyverno verifyImages), progressive delivery (Argo Rollouts canary with the error-rate
SLO as the analysis), a central reusable-workflows repo shared by all services, remote Terraform
state + OIDC apply, and Alertmanager routing to on-call.
