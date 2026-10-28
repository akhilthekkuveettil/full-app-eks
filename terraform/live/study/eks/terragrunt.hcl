include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/terraform/modules/eks"
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs                            = { private_subnet_ids = ["subnet-00000000", "subnet-11111111"] }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  cluster_name = include.root.locals.cluster_name
  subnet_ids   = dependency.vpc.outputs.private_subnet_ids

  # public API endpoint is open to everyone for the study; set ["<your ip>/32"] to restrict
  public_access_cidrs = ["0.0.0.0/0"]

  # kubectl from the laptop; the CI role is admin already because it created the cluster
  admin_principal_arns = ["arn:aws:iam::065148239770:user/admin"]
}
