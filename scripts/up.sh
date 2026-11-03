#!/usr/bin/env bash
# Create the whole stack from nothing: AWS infrastructure (Terragrunt), images, Argo CD, the shared ALB with its
# Ingresses, the app and the monitoring stack. Takes about 20-25 minutes. Safe to run again: every step skips work that is done.
#   scripts/up.sh [-y] [--no-monitoring]
# -y skips the question; --no-monitoring leaves out Prometheus and Grafana (about 6 pods and 1 GB of memory less).
# One-time before the first run: the read-only deploy key for Argo CD (this script makes it and tells you what to do).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
need aws terragrunt terraform docker kubectl helm curl ssh-keygen

MONITORING=1
for a in "$@"; do [ "$a" = --no-monitoring ] && MONITORING=0; done

echo "==> 0/8 checks"
[ -n "$IMAGE_TAG" ] || { echo "no newTag in kubernetes/kustomization.yaml" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "docker is not running" >&2; exit 1; }
if [ ! -f "$ARGOCD_KEY" ]; then
  mkdir -p "$(dirname "$ARGOCD_KEY")"
  ssh-keygen -t ed25519 -N "" -C argocd-readonly -f "$ARGOCD_KEY" >/dev/null
  echo "Made the Argo CD deploy key: $ARGOCD_KEY"
  echo "Add this PUBLIC key in GitHub: repository Settings, Deploy keys, Add deploy key (leave 'Allow write access' off):"
  echo
  cat "$ARGOCD_KEY.pub"
  echo
  echo "Then run scripts/up.sh again. Nothing was created in AWS."
  exit 1
fi

confirm "This creates an EKS cluster, RDS, NAT gateway and one shared load balancer (about \$0.40/hour until scripts/down.sh)." "$@"

echo "==> 1/8 infrastructure (vpc, ecr, eks, rds, alb-controller)"
(cd "$LIVE" && terragrunt run --all --non-interactive --backend-bootstrap apply)

echo "==> 2/8 kubectl access"
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER" >/dev/null
kubectl wait --for=condition=Ready nodes --all --timeout=300s
kubectl -n kube-system rollout status deploy/aws-load-balancer-controller --timeout=300s

echo "==> 3/8 images (tag $IMAGE_TAG, built from this working tree when ECR does not have it)"
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

echo "==> 4/8 database secret"
kubectl apply -f "$ROOT/kubernetes/namespace.yaml"
DATABASE_URL=$(cd "$LIVE/rds" && terragrunt output -raw database_url 2>/dev/null)
kubectl create secret generic database -n app --from-literal=DATABASE_URL="$DATABASE_URL" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> 5/8 Argo CD (with its Ingress on the shared load balancer)"
ARGOCD_CHART_VERSION=$(sed -n 's/^ *ARGOCD_CHART_VERSION: *//p' "$ROOT/.github/workflows/deploy.yml" | head -1)
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null
helm upgrade --install argocd argo/argo-cd --version "$ARGOCD_CHART_VERSION" \
  -n argocd --create-namespace -f "$ROOT/argocd/values.yaml" --wait --timeout 10m

echo "==> 6/8 let Argo CD read the repository"
kubectl -n argocd create secret generic repo-full-app-eks \
  --from-literal=type=git --from-literal=url="$REPO_URL" --from-file=sshPrivateKey="$ARGOCD_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n argocd label secret repo-full-app-eks argocd.argoproj.io/secret-type=repository --overwrite >/dev/null

echo "==> 7/8 applications (the app, and monitoring unless --no-monitoring)"
kubectl apply -f "$ROOT/argocd/application.yaml"
if [ "$MONITORING" = 1 ]; then
  kubectl apply -f "$ROOT/platform/storageclass-gp3.yaml"
  kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
  # first run only: a random Grafana admin password, kept in the cluster and never in git
  kubectl -n monitoring get secret grafana-admin >/dev/null 2>&1 || \
    kubectl -n monitoring create secret generic grafana-admin \
      --from-literal=admin-user=admin --from-literal=admin-password="$(openssl rand -base64 24 | tr -d '/+=')"
  kubectl apply -f "$ROOT/argocd/monitoring.yaml"
fi

wait_app() {
  local state=
  for _ in $(seq 1 60); do
    state=$(kubectl -n argocd get application "$1" -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || true)
    [ "$state" = Synced/Healthy ] && { echo "$1: $state"; return 0; }
    sleep 10
  done
  echo "$1 is not Synced/Healthy yet ($state): kubectl -n argocd get application $1" >&2
  return 1
}

echo "==> 8/8 waiting for Argo CD to roll everything out"
wait_app app || true
if [ "$MONITORING" = 1 ]; then wait_app monitoring || true; fi

HOST=
for _ in $(seq 1 40); do
  HOST=$(kubectl get ingress frontend -n app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [ -n "$HOST" ] && break
  sleep 10
done
[ -n "$HOST" ] || { echo "no load balancer address yet; check: kubectl get ingress -A" >&2; exit 1; }
for _ in $(seq 1 30); do
  [ "$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 -H 'Host: k8application.aryanconcretespares.in' "https://$HOST/" || true)" = 200 ] && break
  sleep 10
done

echo
echo "Everything is up. The load balancer address changes on every rebuild, so in GoDaddy point these CNAMEs at it:"
echo "  k8application, argocd$([ "$MONITORING" = 1 ] && echo ', monitoring')  ->  $HOST"
echo
echo "  https://k8application.aryanconcretespares.in"
echo "  https://argocd.aryanconcretespares.in   user admin, password: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)"
if [ "$MONITORING" = 1 ]; then
  echo "  https://monitoring.aryanconcretespares.in   user admin, password: kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d"
fi
echo
echo "Costs about \$0.40/hour until you run scripts/down.sh"
