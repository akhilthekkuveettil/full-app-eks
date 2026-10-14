variable "zone_id" {
  description = "Route 53 hosted zone id."
  type        = string
}

variable "name" {
  description = "Record name, e.g. app.example.com."
  type        = string
}

variable "target_dns_name" {
  description = "DNS name of the load balancer."
  type        = string
}

variable "target_zone_id" {
  description = "Canonical hosted zone id of the load balancer."
  type        = string
}
