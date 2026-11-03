#!/usr/bin/env bash
# Destroy everything that costs money: Argo CD and the app (which deletes the shared load balancer), then all AWS
# infrastructure (EKS, RDS, NAT, VPC, ECR with its images). The Terraform state bucket is kept.
#   scripts/down.sh [-y]
# Asks for confirmation; -y skips the question. The database and its data are deleted.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
need aws terragrunt terraform kubectl helm

confirm "This deletes the cluster '$CLUSTER', the database and all images." "$@"

echo "==> 1/3 remove the apps and Argo CD (Terraform does not know about the load balancer they create)"
if aws eks describe-cluster --region "$REGION" --name "$CLUSTER" >/dev/null 2>&1; then
  aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER" >/dev/null
  # first the Applications, or Argo CD would recreate what is deleted
  kubectl -n argocd delete application app monitoring --ignore-not-found --timeout=120s || true
  helm uninstall argocd -n argocd >/dev/null 2>&1 || true
  # deleting the namespaces removes the Ingresses and the disks; the controller then deletes the ALB
  kubectl delete namespace app monitoring argocd --ignore-not-found --timeout=300s || true
else
  echo "cluster not found, skipping"
fi

echo "==> 2/3 wait for the load balancer to disappear"
for _ in $(seq 1 30); do
  left=$(aws elbv2 describe-load-balancers --region "$REGION" \
    --query "length(LoadBalancers[?starts_with(LoadBalancerName, 'k8s-')])" --output text 2>/dev/null || echo 0)
  [ "$left" = 0 ] && break
  sleep 10
done

echo "==> 3/3 destroy the infrastructure"
(cd "$LIVE" && terragrunt run --all --non-interactive destroy)

echo
echo "Everything is destroyed. State bucket app-tfstate-$ACCOUNT_ID-$REGION is kept (a few cents per month)."
