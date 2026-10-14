variable "name" {
  description = "Cluster name."
  type        = string
}

variable "kubernetes_version" {
  type    = string
  default = "1.36"
}

variable "subnet_ids" {
  description = "Private subnets for the control plane ENIs and the nodes."
  type        = list(string)
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. Required: no open-to-the-world default."
  type        = list(string)
}

variable "instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "node_disk_size_gb" {
  type    = number
  default = 20
}

variable "admin_principal_arns" {
  description = "Extra IAM principals given cluster-admin. The identity running Terraform is admin already."
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  type    = number
  default = 30
}
