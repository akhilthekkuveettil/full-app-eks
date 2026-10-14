variable "name" {
  description = "IAM role name."
  type        = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  description = "Cluster OIDC issuer without https://."
  type        = string
}

variable "namespace" {
  type = string
}

variable "service_account" {
  type = string
}

variable "policy_json" {
  description = "IAM policy document (JSON) attached to the role."
  type        = string
}
