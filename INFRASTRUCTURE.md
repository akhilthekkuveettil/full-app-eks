# Infrastructure

How the production environment for this application is built and what runs where.
For how code gets from a commit to the cluster, see [WORKFLOW.md](WORKFLOW.md).

## Overview

| | |
|---|---|
| Cloud / account | AWS, account `426737295553` |
| Region | `us-east-1` (everything lives here) |
| Compute | EKS cluster `app-prod`, Kubernetes 1.36, one managed node group of 2 × `t3.medium` in private subnets |
| Database | RDS PostgreSQL 16, `db.t4g.micro`, single-AZ, private |
| Images | ECR repositories `app/backend1..4` and `app/frontend` |
| Delivery | GitHub Actions builds and pushes images; Argo CD deploys from this repository |
| Public URL | `https://app.officialkart.in` (Route 53 + ALB + ACM) |

```
                        GitHub Actions (OIDC, no stored AWS keys)
                    test -> scan -> build -> push by digest -> cosign sign
                                        |
                                        v
                                  ECR  app/*
                                        ^
                                        | pulled by digest
 Browser --HTTPS--> Route 53 --> ALB (public subnets, ACM cert)
                                   |  target-type ip
                  +----------------v------------------------- EKS app-prod (private subnets)
                  |  namespace app                                                         |
                  |   frontend (nginx) --/api/backendN--> backend1..4 (FastAPI) ---5432---> RDS Postgres
                  |                                                                         |
                  |  argocd | kube-system (LB controller) | external-secrets | reloader     |
                  +-------------------------------------------------------------------------+
                                        ^
                                        | git (deploy/ on main)
                                     Argo CD
```

## Repository layout

```
backend1..4/        FastAPI services (same code, different SERVICE_NAME)
frontend/           Angular app served by nginx
docker-compose.yml  local development stack
infra/terraform/    all AWS infrastructure (modules + two stacks)
deploy/             everything Argo CD applies to the cluster
.github/workflows/  CI and image publishing
```

## Terraform

Everything is built from small reusable modules; the stacks only wire them together.

```
infra/terraform/
  modules/
    state-bucket/   S3 bucket for Terraform state (versioned, AES256, TLS only)
    vpc/            VPC, public + private subnets in 2 AZs, one NAT gateway, S3 gateway endpoint
    ecr/            repositories: immutable tags, scan on push, lifecycle policy
    eks/            cluster, KMS secret encryption, node group, IRSA OIDC provider, core add-ons
    rds/            Postgres instance, subnet group, security group, parameter group
    irsa-role/      IAM role assumable by exactly one Kubernetes service account
    github-oidc/    GitHub OIDC provider and the role CI uses to push to ECR
    acm-cert/       ACM certificate validated through Route 53
    dns-alias/      Route 53 alias record pointing at a load balancer
  bootstrap/        creates the state bucket (applied once)
  prod/             creates everything else
```

### State and apply order

State lives in `s3://app-tfstate-426737295553-use1` with native S3 locking
(`use_lockfile`), no DynamoDB table.

1. `bootstrap/` creates the bucket. It is applied once with local state; after that its own
   state should be migrated into the bucket (`terraform init -migrate-state`) and the local
   `terraform.tfstate` deleted.
2. `prod/` stores its state at `prod/terraform.tfstate` in the same bucket.

`prod/terraform.tfvars` is git-ignored and must contain the CIDRs allowed to reach the
Kubernetes API:

```hcl
api_allowed_cidrs = ["<your public IP>/32"]
```

Run `terraform init -reconfigure` first in a fresh checkout. `terraform plan` before every
`apply`, and read the plan: the RDS instance has deletion protection and a final snapshot, but a
replace is still disruptive.

### What `prod` creates

| Area | Details |
|---|---|
| Network | VPC `10.0.0.0/16`; 2 public + 2 private subnets; one NAT gateway (single point of egress, chosen for cost); free S3 gateway endpoint so image layer pulls skip the NAT |
| EKS | Public API endpoint restricted to `api_allowed_cidrs` plus a private endpoint; access via EKS access entries (no `aws-auth`); secrets envelope-encrypted with a KMS key; api/audit/authenticator logs to CloudWatch (30 days) |
| Nodes | Managed node group, AL2023, 2 desired / 2 min / 3 max; IMDSv2 required with hop limit 1 so pods cannot read node credentials; encrypted gp3 root volumes |
| Add-ons | `vpc-cni` with NetworkPolicy enforcement enabled, `kube-proxy`, `coredns` |
| IRSA | OIDC provider for the cluster; roles for the AWS Load Balancer Controller and External Secrets |
| RDS | Encrypted, not publicly accessible, TLS enforced (`rds.force_ssl=1`), 7-day backups, deletion protection, master password managed by RDS in Secrets Manager (rotation interval pushed to 1000 days for now, see below). Security group allows 5432 only from the EKS cluster security group |
| ECR | Immutable tags, scan on push, AES256, keep the 10 most recent images per repository |
| CI access | GitHub OIDC provider and role `app-github-ecr-push`. Trust is pinned to this repository's `main` branch using GitHub's immutable owner/repo IDs; permissions are ECR push to the five `app/*` repositories only |
| TLS / DNS | ACM certificates for `app.officialkart.in` and `argocd.officialkart.in` (DNS-validated in Route 53) and alias records to the ALBs the Ingresses create |
| Argo CD access | Own ALB whose security group (`alb-security-group` module) allows 80/443 only from `argocd_allowed_cidrs` (defaults to `api_allowed_cidrs`); the CIDRs live in the git-ignored `terraform.tfvars`, never in git |

## Kubernetes layer (`deploy/`)

Argo CD is installed once by `deploy/bootstrap/install-argocd.sh`. It applies a root
Application that watches `deploy/apps/` (app-of-apps), which in turn creates:

| Application | Chart | Namespace | Purpose |
|---|---|---|---|
| `aws-load-balancer-controller` | eks-charts 3.5.0 | `kube-system` | Creates the ALB for the Ingress (IRSA role from Terraform) |
| `external-secrets` | external-secrets 2.11.0 | `external-secrets` | Reads the RDS secret from Secrets Manager (IRSA role from Terraform) |
| `reloader` | stakater 2.2.17 | `reloader` | Restarts pods when the database secret changes |
| `app` | `deploy/charts/app` + `deploy/envs/prod.yaml` | `app` | The application itself |

### The application chart

* **Workloads**: `frontend` and `backend1..4`, 2 replicas each, pod disruption budgets
  (`minAvailable: 1`), topology spread across nodes, probes on `/health` (backends) and `/`
  (frontend).
* **Images** are referenced by digest (`registry/app/<name>@sha256:...`). The digests live in
  `deploy/envs/prod.yaml`.
* **Pod hardening**: non-root, `readOnlyRootFilesystem`, all capabilities dropped,
  `RuntimeDefault` seccomp, no service account token mounted. The namespace is labelled
  Pod Security `restricted`.
* **Network policies**: default deny for ingress and egress, then only
  ALB -> frontend:8080, frontend -> backends:8000, backends -> VPC CIDR:5432 (RDS), plus DNS.
* **Ingress**: ALB, internet-facing, HTTP redirected to HTTPS, TLS 1.3 policy
  (`ELBSecurityPolicy-TLS13-1-2-2021-06`), invalid headers dropped.

### How the database credentials reach the pods

```
RDS-managed secret (Secrets Manager) --External Secrets (IRSA)--> k8s Secret "database"
   {username, password}                 builds DATABASE_URL        key DATABASE_URL
                                        postgresql://user:pw@host:5432/appdb?sslmode=require
                                                                          |
                                                          backend pods (env, secretKeyRef)
```

The password never appears in Terraform state or git. The backends refuse to start without
`DATABASE_URL` (there is no default). Reloader restarts the pods if the secret changes.

## Cost (rough, us-east-1, on-demand)

| Item | Per month |
|---|---|
| EKS control plane | ~$73 |
| 2 × t3.medium nodes | ~$60 |
| NAT gateway | ~$35 plus data |
| RDS db.t4g.micro + storage | ~$15 |
| ALB | ~$20 |
| CloudWatch logs, KMS key, Secrets Manager | a few dollars |
| **Total** | **~$200-220** |

These are estimates; check the AWS pricing calculator and set a budget alert.

## Day-to-day operations

```bash
# kubectl access (your IP must be in api_allowed_cidrs)
aws eks update-kubeconfig --region us-east-1 --name app-prod

# Argo CD UI: https://argocd.officialkart.in (only from the allowed CIDRs), or locally:
kubectl -n argocd port-forward svc/argocd-server 8443:443        # https://localhost:8443
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

# health
kubectl get applications -n argocd
kubectl get pods -n app
kubectl get ingress -n app
```

Restarting everything cleanly: `kubectl rollout restart deployment -n app`.
Scaling nodes: change `node_*_size` in the `eks` module call and apply.

## Known behaviours and gotchas

* **ClusterIP traffic and NetworkPolicy.** The VPC CNI policy agent evaluates egress against the
  Service ClusterIP before kube-proxy translates it. A policy that only selects backend pods
  therefore blocks `frontend -> backendN` by Service name (504 from nginx). The chart allows
  the Service CIDR (`serviceCidr`, `172.20.0.0/16`) on port 8000 in addition to the pod
  selector. If the VPC uses a different range, EKS picks a different Service CIDR; update
  `serviceCidr`.
* **First sync race.** On a brand-new cluster the `app` Application can sync before the load
  balancer controller's admission webhook has endpoints; the Services and the ExternalSecret then
  fail and the sync waits on unhealthy Deployments. Terminate the operation and sync again
  (it retries on its own up to 10 times).
* **Frontend resolves backends by FQDN.** nginx's resolver ignores DNS search domains, so the
  frontend gets `BACKEND_SUFFIX=.<namespace>.svc.cluster.local`.
* **GitHub OIDC subject format.** This account's tokens carry immutable IDs
  (`repo:<owner>@<owner_id>/<repo>@<repo_id>:ref:...`), and the role trusts that exact form. If the
  repository is deleted and recreated, update `github_repo_id`.
* **ECR keeps 10 images per repository.** Each build produces an image plus a cosign signature
  artifact, so ten images is roughly five builds. Raise `keep_images` if you need a longer
  rollback window.
* **Secret rotation.** RDS rotates its managed secret every 7 days by default. The rotation
  interval is pushed to the 1000-day maximum for now; AWS documents the schedule as changeable
  but not as removable. Reloader is installed so rotation can be turned on safely by lowering
  `rotation_interval_days` in the `rds` module.
* **Argo CD admin password** is the auto-generated initial secret. Change it or disable the
  admin account before sharing access.

## Not done yet / next

* Automatic digest bump (a CI job that opens a PR updating `deploy/envs/prod.yaml`).
* Budget alert and CloudWatch alarms (pod restarts, ALB 5xx, RDS CPU / storage).
* Dedicated least-privilege database user for the application instead of the RDS master user.
* Multi-AZ RDS and one NAT gateway per AZ if availability requirements grow.
* Admission policy that only allows cosign-signed images from this registry.
* Migrating `bootstrap` state into the bucket, and removing the leftover ap-south-1 resources from
  the earlier attempt (ECR repositories, state bucket, DynamoDB lock table, KMS key, Bitbucket
  OIDC provider and role).

## Tearing down

Deletion protection is on for RDS and the state bucket has `prevent_destroy`. To destroy the
environment: delete the Argo `app` Application and wait for the ALB to disappear (otherwise
the VPC cannot be deleted), set `deletion_protection = false` on the database and apply, then
`terraform destroy` in `prod/`. Leave `bootstrap/` alone unless you are abandoning the account's
state.
