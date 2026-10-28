# Shared settings for up.sh and down.sh (sourced, not run).
REGION=us-east-1
CLUSTER=app-study
SERVICES="backend1 backend2 backend3 backend4 frontend"
IMAGE_TAG=v1

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

# kubernetes/kustomization.yaml holds ACCOUNT_ID / REGION placeholders; fill them on the fly
render() {
  kubectl kustomize "$ROOT/kubernetes" | sed "s/ACCOUNT_ID/$ACCOUNT_ID/g; s/REGION/$REGION/g"
}

# confirm "<what will happen>" "$@"  -- asks for 'yes' unless -y was passed to the script
confirm() {
  local message=$1
  shift
  echo "AWS account $ACCOUNT_ID, region $REGION"
  echo "$message"
  case "${1:-}" in -y) return 0 ;; esac
  read -r -p "Type 'yes' to continue: " answer
  [ "$answer" = yes ] || { echo "aborted"; exit 1; }
}
