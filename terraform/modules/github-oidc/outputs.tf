output "role_arns" {
  description = "Role ARNs to put in the workflows: plan, images, infra"
  value       = { for k, r in aws_iam_role.this : k => r.arn }
}
