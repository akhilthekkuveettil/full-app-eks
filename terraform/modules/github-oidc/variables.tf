variable "name" {
  description = "Name prefix for the IAM roles"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository allowed to assume the roles, as owner/name"
  type        = string
}

variable "github_owner_id" {
  description = "Numeric id of the GitHub owner; GitHub puts it in the token subject (repo:owner@id/name@id:...)"
  type        = number
}

variable "github_repo_id" {
  description = "Numeric id of the GitHub repository, from the same token subject"
  type        = number
}

variable "branch" {
  description = "Branch whose workflows may push images and apply infrastructure"
  type        = string
  default     = "master"
}

variable "ecr_repository_prefix" {
  description = "ECR repositories the image role may push to, e.g. app/ for app/backend1"
  type        = string
  default     = "app/"
}
