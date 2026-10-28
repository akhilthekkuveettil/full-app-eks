include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/terraform/modules/ecr"
}

inputs = {
  repositories = [
    "app/backend1",
    "app/backend2",
    "app/backend3",
    "app/backend4",
    "app/frontend",
  ]
}
