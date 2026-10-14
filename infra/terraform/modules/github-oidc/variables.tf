variable "role_name" {
  type    = string
  default = "app-github-ecr-push"
}

variable "github_repo" {
  description = "owner/name of the repo allowed to assume the role."
  type        = string
}

variable "github_owner_id" {
  description = "Numeric GitHub owner (user/org) id. With github_repo_id, the trust uses GitHub's immutable-id subject format."
  type        = number
  default     = null
}

variable "github_repo_id" {
  description = "Numeric GitHub repository id."
  type        = number
  default     = null
}

variable "branch" {
  type    = string
  default = "main"
}

variable "ecr_repository_arns" {
  description = "Repositories the role may push to."
  type        = list(string)
}
