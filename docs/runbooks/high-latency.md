# HighLatencyP95

**Meaning.** For 10 minutes, 5% of requests to a service took longer than 500 ms.

**Check**
1. Grafana → *Services (RED)* → latency p95 and requests/s: is traffic higher than usual?
2. `kubectl -n demo-<env> top pods` (CPU throttling or memory pressure?)
3. `kubectl -n demo-<env> get hpa`: is the autoscaler already at `maxReplicas`?

**Fix**
- Load is the cause → raise `autoscaling.maxReplicas` or `resources` in `environments/<env>/<app>.yaml`, then open a PR.
- A new version is the cause → roll back (see [error-budget-burn.md](error-budget-burn.md)).
