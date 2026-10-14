# Security group handed to an ALB through the ingress.k8s.aws "security-groups" annotation,
# so who can reach the load balancer is controlled here (and the allowed CIDRs stay out of git).
resource "aws_security_group" "this" {
  name        = var.name
  description = "Restricted access to ${var.name}"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  count = length(var.allowed_cidrs)

  security_group_id = aws_security_group.this.id
  cidr_ipv4         = var.allowed_cidrs[count.index]
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# port 80 only serves the redirect to HTTPS
resource "aws_vpc_security_group_ingress_rule" "http" {
  count = length(var.allowed_cidrs)

  security_group_id = aws_security_group.this.id
  cidr_ipv4         = var.allowed_cidrs[count.index]
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
