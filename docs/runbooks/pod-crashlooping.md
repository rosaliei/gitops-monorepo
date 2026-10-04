# PodCrashLooping

**Meaning.** A container restarted more than 3 times in 15 minutes.

**Check**
```bash
kubectl -n demo-<env> get pods
kubectl -n demo-<env> describe pod <pod>        # Last State: OOMKilled? probe failed?
kubectl -n demo-<env> logs <pod> --previous      # logs from the crashed container
```

**Fix**
| Cause | Fix (in Git) |
|---|---|
| `OOMKilled` | raise `resources.limits.memory` in `environments/<env>/<app>.yaml` |
| liveness probe fails on startup | check `probes.liveness` path/port |
| bad config / missing secret | check `env` / `secretEnv`, and `kubectl -n demo-<env> get externalsecret` |
| bug in the new version | roll back ([error-budget-burn.md](error-budget-burn.md)) |
