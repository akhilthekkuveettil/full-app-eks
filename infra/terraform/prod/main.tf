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

module "rds" {
  source = "../modules/rds"

  name          = "${var.cluster_name}-db"
  vpc_id        = module.vpc.vpc_id
  subnet_ids    = module.vpc.private_subnet_ids
  allowed_cidrs = module.vpc.private_subnet_cidrs
}
