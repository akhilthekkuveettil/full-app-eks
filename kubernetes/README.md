# Kubernetes manifests

Applied to the cluster built by `terraform/`. The quick way is `scripts/up.sh` (create everything) and
`scripts/down.sh` (destroy everything). The manual steps below do the same thing.

Namespace `app`: frontend (nginx) + backend1..4 (FastAPI) + an ALB Ingress. The database is RDS;
its URL comes from the Secret `database`, which is created by a command and is not in git.

```bash
kubectl apply -f kubernetes/namespace.yaml
kubectl create secret generic database -n app \
  --from-literal=DATABASE_URL="$(cd terraform/live/study/rds && terragrunt output -raw database_url)"
kubectl kustomize kubernetes | sed "s/ACCOUNT_ID/$ACCOUNT_ID/g; s/REGION/$REGION/g" | kubectl apply -f -
kubectl get pods -n app -w
kubectl get ingress frontend -n app      # ADDRESS column = the ALB hostname (2-3 min), open http://<ADDRESS>
```

Image names in `kustomization.yaml` contain `ACCOUNT_ID` and `REGION` placeholders; the scripts and the
`sed` above fill them in when applying.

Handy:

```bash
kubectl logs deploy/backend1 -n app
kubectl describe pod <pod> -n app
kubectl rollout restart deploy -n app
```

New version: push images with a new tag, change `newTag` in `kustomization.yaml`, re-apply.
