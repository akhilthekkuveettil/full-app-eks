# Shared settings for every unit under live/. Each unit's terragrunt.hcl includes this file.

locals {
  region       = "us-east-1"
  project      = "app"
  env          = "study"
  cluster_name = "app-study"
  account_id   = get_aws_account_id()
}

# State goes to one S3 bucket per account; terragrunt creates the bucket on first run.
# use_lockfile = native S3 locking, no DynamoDB table needed.
remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket       = "${local.project}-tfstate-${local.account_id}-${local.region}"
    key          = "${path_relative_to_include()}/terraform.tfstate"
    region       = local.region
    encrypt      = true
    use_lockfile = true
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF2
    provider "aws" {
      region = "${local.region}"

      default_tags {
        tags = {
          project    = "${local.project}"
          env        = "${local.env}"
          managed-by = "terragrunt"
        }
      }
    }
  EOF2
}
