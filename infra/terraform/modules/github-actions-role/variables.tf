variable "name" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "github_repo" {
  description = "owner/name of the repository."
  type        = string
}

variable "github_owner_id" {
  description = "Numeric id of the GitHub account that owns the repository."
  type        = number
}

variable "github_repo_id" {
  description = "Numeric id of the repository."
  type        = number
}

variable "subject_suffixes" {
  description = "What may assume the role, e.g. [\"pull_request\", \"ref:refs/heads/main\", \"environment:production-infra\"]."
  type        = list(string)
}

variable "managed_policy_arns" {
  type    = list(string)
  default = []
}

variable "inline_policy_json" {
  type    = string
  default = null
}
