output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_security_group_id" {
  description = "Security group attached to the nodes (the databases allow traffic from it)"
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.this.arn
}

output "oidc_provider_url" {
  description = "Issuer URL without the https:// prefix"
  value       = replace(aws_iam_openid_connect_provider.this.url, "https://", "")
}

output "cluster_ca_data" {
  description = "Base64 CA certificate of the Kubernetes API"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}
