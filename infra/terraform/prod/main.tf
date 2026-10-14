module "vpc" {
  source = "../modules/vpc"

  name = var.cluster_name
  cidr = var.vpc_cidr
}

module "ecr" {
  source = "../modules/ecr"

  repositories = [for s in var.services : "app/${s}"]
}

module "github_oidc" {
  source = "../modules/github-oidc"

  github_repo         = var.github_repo
  github_owner_id     = var.github_owner_id
  github_repo_id      = var.github_repo_id
  ecr_repository_arns = module.ecr.repository_arns
}

module "eks" {
  source = "../modules/eks"

  name                 = var.cluster_name
  kubernetes_version   = var.kubernetes_version
  subnet_ids           = module.vpc.private_subnet_ids
  public_access_cidrs  = var.api_allowed_cidrs
  admin_principal_arns = var.admin_principal_arns
}

module "rds" {
  source = "../modules/rds"

  name       = "${var.cluster_name}-db"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  # only the cluster's nodes may reach Postgres
  allowed_security_group_ids = [module.eks.cluster_security_group_id]
}

# ---- IAM for cluster add-ons (installed later by Argo CD) --------------------

module "irsa_lb_controller" {
  source = "../modules/irsa-role"

  name              = "${var.cluster_name}-aws-load-balancer-controller"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  namespace         = "kube-system"
  service_account   = "aws-load-balancer-controller"
  policy_json       = file("${path.module}/policies/aws-load-balancer-controller.json")
}

data "aws_iam_policy_document" "external_secrets" {
  statement {
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [module.rds.master_user_secret_arn]
  }
}

module "irsa_external_secrets" {
  source = "../modules/irsa-role"

  name              = "${var.cluster_name}-external-secrets"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  namespace         = "external-secrets"
  service_account   = "external-secrets"
  policy_json       = data.aws_iam_policy_document.external_secrets.json
}

# ---- TLS certificate for the public hostname ---------------------------------

module "app_cert" {
  source = "../modules/acm-cert"

  domain_name = var.app_hostname
  zone_id     = var.hosted_zone_id
}

# ---- DNS: points the hostname at the ALB that the Ingress created --------------
# The ALB is created by the AWS Load Balancer Controller from the Ingress (not by Terraform),
# so it is looked up by the tag the controller puts on it. Set create_app_dns_record = false
# on a fresh cluster until the Ingress has an address.
data "aws_lb" "app" {
  count = var.create_app_dns_record ? 1 : 0

  tags = {
    "ingress.k8s.aws/stack" = "app/app"
  }
}

module "app_dns" {
  count  = var.create_app_dns_record ? 1 : 0
  source = "../modules/dns-alias"

  zone_id         = var.hosted_zone_id
  name            = var.app_hostname
  target_dns_name = data.aws_lb.app[0].dns_name
  target_zone_id  = data.aws_lb.app[0].zone_id
}
