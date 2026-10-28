# Applied by hand once (see terraform/README.md): GitHub Actions cannot create the thing it logs in with.
# Kept outside live/study so the workflow's "run --all apply" never rewrites its own roles.
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/terraform/modules/github-oidc"
}

inputs = {
  name        = "app"
  github_repo = "akhilthekkuveettil/full-app-eks"
}
