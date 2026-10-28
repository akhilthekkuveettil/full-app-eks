#!/usr/bin/env bash
# Destroy everything that costs money: the app and its load balancer, then all AWS infrastructure
# (EKS, RDS, NAT, VPC, ECR with its images). The Terraform state bucket is kept.
# Asks for confirmation; -y skips the question. The database and its data are deleted.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
need aws terragrunt terraform kubectl

confirm "This deletes the cluster '$CLUSTER', the database and all images." "$@"

echo "==> 1/2 remove the app (this deletes the ALB; Terraform does not know about it)"
if aws eks describe-cluster --region "$REGION" --name "$CLUSTER" >/dev/null 2>&1; then
  aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER" >/dev/null
  # deleting the namespace removes the Ingress; the controller then deletes the ALB
  kubectl delete namespace app --ignore-not-found --timeout=300s
  # the controller removes the ALB and its security groups after the Ingress is gone
  sleep 30
else
  echo "cluster not found, skipping"
fi

echo "==> 2/2 destroy the infrastructure"
(cd "$LIVE" && terragrunt run --all destroy)

echo
echo "Everything is destroyed. State bucket app-tfstate-$ACCOUNT_ID-$REGION is kept (a few cents per month)."
