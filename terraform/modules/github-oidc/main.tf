# Lets GitHub Actions log in to AWS without stored keys. Three roles, each trusted for one kind of workflow run:
#   plan    pull requests            read-only, so a plan can never change anything
#   images  pushes to the branch     push images to ECR only
#   infra   the approved environment administrator, used by terragrunt apply (it creates IAM roles, EKS, RDS ...)
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

locals {
  roles = {
    plan   = { subject = "pull_request", policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess" }
    images = { subject = "ref:refs/heads/${var.branch}", policy_arn = null }
    infra  = { subject = "environment:${var.environment}", policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess" }
  }
}

data "aws_iam_policy_document" "assume" {
  for_each = local.roles

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:${each.value.subject}"]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = local.roles

  name                 = "${var.name}-github-${each.key}"
  assume_role_policy   = data.aws_iam_policy_document.assume[each.key].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = { for k, v in local.roles : k => v.policy_arn if v.policy_arn != null }

  role       = aws_iam_role.this[each.key].name
  policy_arn = each.value
}

data "aws_iam_policy_document" "images" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = ["arn:aws:ecr:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:repository/${var.ecr_repository_prefix}*"]
  }
}

resource "aws_iam_role_policy" "images" {
  name   = "ecr-push"
  role   = aws_iam_role.this["images"].id
  policy = data.aws_iam_policy_document.images.json
}
