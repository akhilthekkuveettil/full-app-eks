variable "name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "cidr" {
  description = "VPC address range"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones (one public and one private subnet each)"
  type        = number
  default     = 2
}

variable "cluster_name" {
  description = "EKS cluster name, used in the subnet tags the load balancer controller looks for"
  type        = string
}
