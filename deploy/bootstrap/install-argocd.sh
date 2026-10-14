#!/usr/bin/env bash
# One-time: install Argo CD into the cluster, then hand control to the root app.
# Needs: kubectl context pointing at app-prod (aws eks update-kubeconfig --name app-prod).
set -euo pipefail

CHART_VERSION=10.10.0
here="$(cd "$(dirname "$0")" && pwd)"

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update argo >/dev/null

helm upgrade --install argocd argo/argo-cd \
  --version "$CHART_VERSION" \
  --namespace argocd --create-namespace \
  --wait --timeout 10m

kubectl apply -f "$here/root-app.yaml"

echo
echo "Argo CD is up. UI:  kubectl -n argocd port-forward svc/argocd-server 8443:443"
echo "Admin password:     kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
