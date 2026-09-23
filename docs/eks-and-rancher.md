# Running on EKS or a Rancher cluster

Nothing in `charts/`, `environments/` or `argocd/` is specific to kind. Only **how the cluster is
created** and **where secrets come from** change.

| | kind (laptop) | EKS | Rancher-managed (RKE2 / imported) |
|---|---|---|---|
| Create cluster | `kind create cluster` | `terraform apply` in `infra/eks` | Rancher UI / RKE2 |
| Install ArgoCD | `scripts/bootstrap.sh` | same | same |
| Secret store | `fake` provider (demo values) | AWS Secrets Manager + Pod Identity | Vault / cloud secret manager |
| Ingress | `kubectl port-forward` | AWS Load Balancer Controller | the cluster's ingress / Gateway API |

## EKS

### 1. By hand
```bash
cd infra/eks
terraform init
terraform plan -out tfplan      # read it: VPC, NAT, EKS, node group
terraform apply tfplan          # ~15 min
aws eks update-kubeconfig --name gitops-demo --region ap-southeast-1
kubectl get nodes

# Same GitOps bootstrap as on the laptop, minus the kind step:
helm upgrade --install argocd argo-cd --repo https://argoproj.github.io/argo-helm --version 10.9.2 \
  -n argocd --create-namespace -f infra/kind/argocd-values.yaml
kubectl apply -f argocd/bootstrap/root-app.yaml

# Real secrets: swap the store for AWS Secrets Manager
cp infra/eks/cluster-secret-store-aws.yaml platform/manifests/secrets/cluster-secret-store.yaml
aws secretsmanager create-secret --name prod/orders-api/api-key --secret-string "$(openssl rand -hex 16)"
# + an EKS Pod Identity association that lets the external-secrets service account read them
```
Clean up: `terraform destroy` (EKS + NAT are billed per hour).

### 2. Automation
- `.github/workflows/terraform.yaml` runs `fmt`, `init` and `validate` on every PR that touches `infra/eks`.
- `apply` is **not** run from CI here on purpose (no cloud credentials in a public repo). In a team:
  `plan` runs on the PR and the plan is posted as a comment. `apply` runs after merge, using
  **GitHub OIDC → an IAM role** (no long-lived AWS keys) and a protected `infrastructure` environment.

## Rancher

Rancher is the **cluster management** layer (create/import clusters, RBAC, UI). ArgoCD stays the
**deployment** layer. Import the cluster into Rancher, then bootstrap ArgoCD exactly as above.

The one thing to watch: people can edit workloads in the Rancher UI. With server-side apply,
ArgoCD's self-heal does **not** revert fields it does not own (e.g. an env var added in Rancher),
so the drift would stay. The `block-manual-changes` admission policy
([platform/manifests/policies](../platform/manifests/policies/block-manual-changes.yaml)) rejects
those edits in `demo-*` namespaces, so Git stays the only way in.

(Rancher also ships Fleet, its own GitOps engine. This repo uses ArgoCD so that one tool is used
everywhere, whichever cluster it runs on.)
