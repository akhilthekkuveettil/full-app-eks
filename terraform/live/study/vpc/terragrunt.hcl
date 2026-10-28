include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/terraform/modules/vpc"
}

inputs = {
  name         = include.root.locals.cluster_name
  cluster_name = include.root.locals.cluster_name
}
