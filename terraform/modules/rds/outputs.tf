output "endpoint" {
  value = aws_db_instance.this.address
}

output "database_url" {
  description = "Connection string for the backends (RDS requires TLS, hence sslmode=require)"
  value       = "postgresql://${var.username}:${random_password.this.result}@${aws_db_instance.this.address}:5432/${var.db_name}?sslmode=require"
  sensitive   = true
}
