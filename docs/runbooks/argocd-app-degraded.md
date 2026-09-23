# ArgoAppDegraded

**Meaning.** ArgoCD applied what is in Git, but the result is not healthy: pods not ready, image
cannot be pulled, rollout stuck.

**Check**
```bash
make status                                           # all apps: sync, health, image
kubectl -n argocd get application <app>-<env> -o yaml | grep -A20 'status:'
kubectl -n demo-<env> get pods,events --sort-by=.lastTimestamp | tail -20
```
Or open the app in the ArgoCD UI (`make ui-argocd`). The red resource tells you where to look.

**Common causes**
| Symptom | Cause | Fix |
|---|---|---|
| `ImagePullBackOff` | tag/digest not in the registry, or the GHCR package is private | check the tag in `environments/<env>/<app>.yaml`, make the package public |
| `CrashLoopBackOff` | the app crashes | [pod-crashlooping.md](pod-crashlooping.md) |
| Progressing for a long time | readiness probe never passes | check `probes.readiness` |

A deploy made it worse → roll back through Git (revert the commit that changed `environments/<env>/`).
