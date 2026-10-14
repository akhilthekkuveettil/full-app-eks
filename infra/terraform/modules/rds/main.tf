resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids
}

resource "aws_security_group" "this" {
  name        = "${var.name}-postgres"
  description = "Postgres access for ${var.name}"
  vpc_id      = var.vpc_id
}

# count, not for_each: the values can be unknown until apply (e.g. a security group created
# in the same run), but the list length is always known.
resource "aws_vpc_security_group_ingress_rule" "cidr" {
  count = length(var.allowed_cidrs)

  security_group_id = aws_security_group.this.id
  cidr_ipv4         = var.allowed_cidrs[count.index]
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "sg" {
  count = length(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = var.allowed_security_group_ids[count.index]
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# Reject non-TLS connections.
resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.name}-pg-"
  family      = "postgres${split(".", var.engine_version)[0]}"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "this" {
  identifier = var.name

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.username
  # RDS creates the password in Secrets Manager; it never lands in Terraform state.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false
  multi_az               = var.multi_az

  backup_retention_period    = var.backup_retention_days
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name}-final"
}

# RDS-managed secrets rotate every 7 days by default, which would invalidate the password the
# pods started with. Push the schedule to the Secrets Manager maximum until the cluster has
# a restart-on-change setup (Reloader); then lower var.rotation_interval_days.
resource "aws_secretsmanager_secret_rotation" "master" {
  secret_id = aws_db_instance.this.master_user_secret[0].secret_arn

  rotation_rules {
    automatically_after_days = var.rotation_interval_days
  }
}
