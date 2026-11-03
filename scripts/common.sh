# Shared settings for up.sh and down.sh (sourced, not run).
REGION=us-east-1
CLUSTER=app-study
SERVICES="backend1 backend2 backend3 backend4 frontend"
# the image tag that kubernetes/kustomization.yaml deploys (the pipeline writes it there)
IMAGE_TAG=$(sed -n 's/^ *newTag: *//p' "$(dirname "${BASH_SOURCE[0]}")/../kubernetes/kustomization.yaml" | head -1)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIVE="$ROOT/terraform/live/study"

# the only AWS account these scripts may touch
EXPECTED_ACCOUNT=065148239770

export AWS_DEFAULT_REGION=$REGION
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text) || {
  echo "cannot read the AWS account (are you logged in?)" >&2
  exit 1
}
if [ "$ACCOUNT_ID" != "$EXPECTED_ACCOUNT" ]; then
  echo "Wrong AWS account: logged in to $ACCOUNT_ID, expected $EXPECTED_ACCOUNT. Nothing was changed." >&2
  exit 1
fi
REGISTRY=$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

need() {
  for t in "$@"; do
    command -v "$t" >/dev/null || { echo "missing tool: $t" >&2; exit 1; }
  done
}

# the read-only SSH key that lets Argo CD read the git repository; kept between up.sh runs, so it is made once
ARGOCD_KEY=${ARGOCD_DEPLOY_KEY:-$HOME/.config/full-app-eks/argocd_deploy}
REPO_URL=$(sed -n 's/^ *repoURL: *//p' "$ROOT/argocd/application.yaml" | head -1)

# confirm "<what will happen>" "$@"  -- asks for 'yes' unless -y was passed to the script
confirm() {
  local message=$1
  shift
  echo "AWS account $ACCOUNT_ID, region $REGION"
  echo "$message"
  for a in "$@"; do [ "$a" = -y ] && return 0; done
  read -r -p "Type 'yes' to continue: " answer
  [ "$answer" = yes ] || { echo "aborted"; exit 1; }
}
