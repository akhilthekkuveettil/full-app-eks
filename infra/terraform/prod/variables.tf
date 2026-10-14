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
