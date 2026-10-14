output "ecr_repositories" {
  value = module.ecr.repository_urls
}

output "ci_role_arn" {
  value = module.github_oidc.role_arn
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "db_address" {
  value = module.rds.address
}

output "db_secret_arn" {
  value = module.rds.master_user_secret_arn
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  value = module.eks.oidc_provider_url
}

output "lb_controller_role_arn" {
  value = module.irsa_lb_controller.role_arn
}

output "external_secrets_role_arn" {
  value = module.irsa_external_secrets.role_arn
}

output "app_certificate_arn" {
  value = module.app_cert.certificate_arn
}
