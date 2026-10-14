variable "region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name; used for naming and subnet discovery tags."
  type        = string
  default     = "app-prod"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "github_repo" {
  description = "owner/name of the GitHub repo allowed to push images."
  type        = string
  default     = "akhilthekkuveettil/full-app-eks"
}

variable "services" {
  type    = list(string)
  default = ["backend1", "backend2", "backend3", "backend4", "frontend"]
}

variable "github_owner_id" {
  description = "Numeric id of the GitHub account that owns the repo (see the sub claim in CloudTrail/the OIDC token)."
  type        = number
  default     = 78824931
}

variable "github_repo_id" {
  description = "Numeric id of the GitHub repository."
  type        = number
  default     = 1418427233
}

variable "kubernetes_version" {
  type    = string
  default = "1.36"
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API (set in terraform.tfvars, e.g. [\"1.2.3.4/32\"])."
  type        = list(string)
}

variable "admin_principal_arns" {
  description = "Extra IAM principals with cluster-admin (the identity running Terraform already is)."
  type        = list(string)
  default     = []
}

variable "hosted_zone_id" {
  description = "Route 53 public hosted zone for the app hostname."
  type        = string
  default     = "Z0603608CMVVXH716EK3"
}

variable "app_hostname" {
  type    = string
  default = "app.officialkart.in"
}
