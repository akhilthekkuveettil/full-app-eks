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

  # three t3.medium nodes (4 GB, 17 pods each): t3.small nodes ran out of memory and went NotReady under monitoring and dev
  node_instance_type = "t3.medium"
  node_count         = 3

  # kubectl from the laptop; the CI role is admin already because it created the cluster
  admin_principal_arns = ["arn:aws:iam::065148239770:user/admin"]

  # developers: read-only on the whole cluster
  viewer_principal_arns = ["arn:aws:iam::065148239770:user/dev-viewer"]
}
