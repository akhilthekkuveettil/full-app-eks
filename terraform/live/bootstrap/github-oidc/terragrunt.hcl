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

  # from the "sub" claim of a workflow run: repo:akhilthekkuveettil@78824931/full-app-eks@1436740181:...
  github_owner_id = 78824931
  github_repo_id  = 1436740181
}
