# HighLatencyP95 / HighLatencyP99

**Meaning.**
- **HighLatencyP95**: for 10 minutes, 1 in 20 requests (5%) took longer than **500 ms**.
- **HighLatencyP99**: for 10 minutes, 1 in 100 requests (1%) took longer than **1 s**. This is the *tail*:
  a few slow requests the average hides, but users notice (and a page that makes 20 calls hits the tail often).

**Percentiles in one line:** p50 = the typical request, p95 = 1 in 20 is slower, p99 = 1 in 100 is slower.
They are estimated from the `http_request_duration_seconds` histogram buckets, so values are approximate
(interpolated inside a bucket).

**Check**
1. Grafana → *Services (RED)* → **Latency p50 / p95 / p99**: is only p99 high (a few slow requests) or all three (everything is slow)?
2. Requests/s in the same dashboard: is traffic higher than usual?
3. `kubectl -n demo-<env> top pods` (CPU throttling or memory pressure?) and `kubectl -n demo-<env> get hpa` (already at `maxReplicas`?)
4. Prometheus: `job:http_request_duration_seconds:p99_5m` (recording rule) to see the exact value per service and environment.

**Fix**
| Pattern | Likely cause | Fix (in Git) |
|---|---|---|
| p50, p95, p99 all high | overload or a slow dependency | raise `autoscaling.maxReplicas` / `resources` in `gitops-config/environments/<env>/<app>.yaml` |
| only p99 high | a slow endpoint, GC pauses, cold caches, a few retries | look at the slow route; profile; increase timeouts carefully |
| started right after a deploy | the new version | roll back (see [error-budget-burn.md](error-budget-burn.md)) |

The rules are unit-tested: `gitops-config/platform/tests/latency-rules.test.yaml` (run by `gitops-config/scripts/validate.sh`).
