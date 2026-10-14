# Terraform

All resources live in reusable modules; the stacks only wire them together.

```
modules/
  state-bucket/   S3 bucket for Terraform state (versioned, encrypted, TLS only)
  vpc/            VPC, public/private subnets, single NAT, S3 endpoint
  ecr/            ECR repositories (immutable tags, scan on push, lifecycle)
  eks/            EKS cluster, managed node group, IRSA OIDC provider, core add-ons
  irsa-role/      IAM role assumable by one Kubernetes service account
  acm-cert/       ACM certificate validated through Route 53
  rds/            Postgres on RDS (private, encrypted, TLS-only, RDS-managed password in Secrets Manager)
  github-oidc/    GitHub OIDC provider + role that can push to ECR from one repo/branch
bootstrap/        applies state-bucket (local state, run once)
prod/             applies vpc + eks + ecr + rds + github-oidc (state in the bucket above)
```

Region is us-east-1 everywhere. Order: `bootstrap` first, then `prod`.
