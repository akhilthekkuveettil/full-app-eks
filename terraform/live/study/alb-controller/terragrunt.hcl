include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_repo_root()}/terraform/modules/alb-controller"
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs                            = { vpc_id = "vpc-00000000" }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_name      = "mock"
    cluster_endpoint  = "https://mock.example.com"
    cluster_ca_data   = "bW9jaw=="
    oidc_provider_arn = "arn:aws:iam::000000000000:oidc-provider/mock"
    oidc_provider_url = "mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# the Helm provider needs the cluster address and a token, which only exist after the eks unit
generate "helm_provider" {
  path      = "provider_helm.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF2
    provider "helm" {
      kubernetes {
        host                   = "${dependency.eks.outputs.cluster_endpoint}"
        cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_ca_data}")

        exec {
          api_version = "client.authentication.k8s.io/v1beta1"
          command     = "aws"
          args        = ["eks", "get-token", "--cluster-name", "${dependency.eks.outputs.cluster_name}", "--region", "${include.root.locals.region}"]
        }
      }
    }
  EOF2
}

inputs = {
  cluster_name      = include.root.locals.cluster_name
  region            = include.root.locals.region
  vpc_id            = dependency.vpc.outputs.vpc_id
  oidc_provider_arn = dependency.eks.outputs.oidc_provider_arn
  oidc_provider_url = dependency.eks.outputs.oidc_provider_url
}
