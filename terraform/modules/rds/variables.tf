variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Private subnets for the database"
  type        = list(string)
}

variable "allowed_security_group_id" {
  description = "Security group allowed to connect on 5432 (the EKS nodes)"
  type        = string
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "username" {
  type    = string
  default = "postgres"
}

variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "storage_gb" {
  type    = number
  default = 20
}
