variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  description = "Kubernetes version; null uses the current EKS default"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Private subnets for the control plane network interfaces and the nodes"
  type        = list(string)
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API endpoint. Restrict to your IP/32 when possible."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_type" {
  type    = string
  default = "t3.small"
}

variable "node_count" {
  type    = number
  default = 2
}

variable "node_disk_size" {
  description = "Node root volume size in GiB"
  type        = number
  default     = 20
}
