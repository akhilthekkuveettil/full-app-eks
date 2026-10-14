output "role_arn" {
  value = aws_iam_role.ci_push.arn
}

output "provider_arn" {
  description = "ARN of the GitHub OIDC identity provider, for additional roles."
  value       = aws_iam_openid_connect_provider.github.arn
}
