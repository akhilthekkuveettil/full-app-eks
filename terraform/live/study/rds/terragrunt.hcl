include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/terraform/modules/rds"
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id             = "vpc-00000000"
    private_subnet_ids = ["subnet-00000000", "subnet-11111111"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs                            = { cluster_security_group_id = "sg-00000000" }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  name                      = include.root.locals.cluster_name
  vpc_id                    = dependency.vpc.outputs.vpc_id
  subnet_ids                = dependency.vpc.outputs.private_subnet_ids
  allowed_security_group_id = dependency.eks.outputs.cluster_security_group_id
}
