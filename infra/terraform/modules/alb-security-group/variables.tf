variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "allowed_cidrs" {
  description = "CIDRs allowed to reach the load balancer on 80/443."
  type        = list(string)
}
