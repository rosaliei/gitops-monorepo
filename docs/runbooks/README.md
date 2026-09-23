# Runbooks

Every alert in [`platform/manifests/monitoring/alerts.yaml`](../../platform/manifests/monitoring/alerts.yaml) links here.
Each runbook answers three questions: **what does it mean, how do I check, how do I fix it.**

| Alert | Severity | Runbook |
|---|---|---|
| ErrorBudgetBurnFast | critical | [error-budget-burn.md](error-budget-burn.md) |
| HighLatencyP95 | warning | [high-latency.md](high-latency.md) |
| PodCrashLooping | warning | [pod-crashlooping.md](pod-crashlooping.md) |
| ArgoAppDegraded | critical | [argocd-app-degraded.md](argocd-app-degraded.md) |
| ArgoAppOutOfSync | warning | [argocd-app-outofsync.md](argocd-app-outofsync.md) |

The golden rule in a GitOps cluster: **fix forward or roll back through Git.** `kubectl edit` is
blocked in `demo-*` namespaces by an admission policy, and ArgoCD would undo it anyway.
