variable "repositories" {
  description = "Repository names to create, e.g. [\"app/backend1\"]"
  type        = list(string)
}

variable "keep_images" {
  description = "Number of most recent images kept per repository"
  type        = number
  default     = 10
}

variable "force_delete" {
  description = "Allow terraform destroy to delete repositories that still contain images"
  type        = bool
  default     = true
}
