#!/usr/bin/env bash
# Create the whole stack: AWS infrastructure (Terragrunt), images, and the app on the cluster.
# Asks for confirmation; -y skips the question. Safe to run again: every step skips work that is already done.
# Takes about 20 minutes the first time.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
need aws terragrunt terraform docker kubectl curl

confirm "This creates an EKS cluster, RDS, NAT gateway and load balancer (about \$0.25/hour until down.sh)." "$@"

echo "==> 1/5 infrastructure (vpc, ecr, eks, rds, alb-controller)"
(cd "$LIVE" && terragrunt run --all --backend-bootstrap apply)

echo "==> 2/5 kubectl access"
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER" >/dev/null
kubectl wait --for=condition=Ready nodes --all --timeout=300s
kubectl -n kube-system rollout status deploy/aws-load-balancer-controller --timeout=300s

echo "==> 3/5 images"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY" >/dev/null
for s in $SERVICES; do
  if aws ecr describe-images --region "$REGION" --repository-name "app/$s" \
       --image-ids imageTag="$IMAGE_TAG" >/dev/null 2>&1; then
    echo "$s:$IMAGE_TAG already in ECR, skipping"
  else
    docker build -q -t "$REGISTRY/app/$s:$IMAGE_TAG" "$ROOT/$s" >/dev/null
    docker push -q "$REGISTRY/app/$s:$IMAGE_TAG" >/dev/null
    echo "pushed $s:$IMAGE_TAG"
  fi
done

echo "==> 4/5 deploy the app"
kubectl apply -f "$ROOT/kubernetes/namespace.yaml"
DATABASE_URL=$(cd "$LIVE/rds" && terragrunt output -raw database_url 2>/dev/null)
kubectl create secret generic database -n app --from-literal=DATABASE_URL="$DATABASE_URL" \
  --dry-run=client -o yaml | kubectl apply -f -
render | kubectl apply -f -
for d in backend1 backend2 backend3 backend4 frontend; do
  kubectl -n app rollout status "deploy/$d" --timeout=300s
done

echo "==> 5/5 waiting for the load balancer address"
for _ in $(seq 1 40); do
  HOST=$(kubectl get ingress frontend -n app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [ -n "$HOST" ] && break
  sleep 10
done
[ -n "${HOST:-}" ] || { echo "no address yet; check: kubectl get ingress -n app" >&2; exit 1; }
for _ in $(seq 1 30); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://$HOST/" || true)" = 200 ] && break
  sleep 10
done

echo
echo "App is up: http://$HOST"
echo "Costs about \$0.25/hour until you run scripts/down.sh"
