# ArgoAppOutOfSync

**Meaning.** For 15 minutes the cluster has not matched Git, even though auto-sync and self-heal
are on. Something is stopping ArgoCD from applying.

**Check**
```bash
kubectl -n argocd get application <app>-<env> -o jsonpath='{.status.operationState.message}'
```

**Common causes**
| Message | Cause | Fix |
|---|---|---|
| `denied request: ValidatingAdmissionPolicy 'safe-deployments'` | the change breaks a policy (`:latest`, no memory limit, root) | fix the values file. CI should have caught it (`make lint e2e`) |
| `resource ... is not permitted in project demo` | a new kind the `demo` AppProject does not allow | add it to `argocd/apps/00-projects.yaml` if it is intended |
| `rpc error ... repository not found` | ArgoCD cannot read the repo | repo URL / credentials in ArgoCD |
| `the server could not find the requested resource` | a CRD is missing (e.g. ExternalSecret before ESO is installed) | wait for the platform apps to sync, or check `external-secrets` / `monitoring` apps |
