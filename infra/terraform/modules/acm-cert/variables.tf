variable "domain_name" {
  description = "Fully qualified name the certificate is issued for."
  type        = string
}

variable "zone_id" {
  description = "Route 53 public hosted zone that contains domain_name."
  type        = string
}
