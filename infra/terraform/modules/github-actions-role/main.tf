# IAM role for GitHub Actions, assumable only through the listed subjects of one repository.
# Uses GitHub's immutable-id subject format: repo:<owner>@<owner_id>/<repo>@<repo_id>:<suffix>
locals {
  owner = split("/", var.github_repo)[0]
  repo  = split("/", var.github_repo)[1]
  base  = "repo:${local.owner}@${var.github_owner_id}/${local.repo}@${var.github_repo_id}"
}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for s in var.subject_suffixes : "${local.base}:${s}"]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = var.name
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "managed" {
  count = length(var.managed_policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = var.managed_policy_arns[count.index]
}

resource "aws_iam_role_policy" "inline" {
  count = var.inline_policy_json == null ? 0 : 1

  name   = var.name
  role   = aws_iam_role.this.id
  policy = var.inline_policy_json
}
