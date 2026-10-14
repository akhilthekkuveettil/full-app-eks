# Workflow

How a change moves from a commit to production, and how to work with the pieces along the way.
For what the infrastructure is, see [INFRASTRUCTURE.md](INFRASTRUCTURE.md).

## The path of a change

```
 feature branch / PR            main                                    cluster
 -------------------            ----                                    -------
 tests + dependency scan  --->  tests + scan + build   --->  publish    update digests     Argo CD
 + image build (no push)        (same as PR)                (push+sign)  in envs/prod.yaml  syncs app
```

1. **Open a pull request.** CI runs tests, dependency scans and image builds. Nothing is pushed.
2. **Merge to `main`.** CI runs again and then the `publish` job pushes signed images to ECR.
3. **Point the deployment at the new images** by updating the digests in
   `deploy/envs/prod.yaml` (currently a manual step, see below).
4. **Argo CD syncs** the change from `main` to the cluster automatically.

## CI: `.github/workflows/ci.yml`

Triggers: pull requests, pushes to `main`, and a weekly schedule (Mondays 06:00 UTC) so newly
published vulnerabilities are caught even without a push. A new push to the same ref cancels
the older run.

| Job | Runs for | What it does |
|---|---|---|
| `backend` (matrix: backend1-4) | PR, main, schedule | Install pinned, hash-checked dependencies; `pytest`; `pip-audit` against `requirements.txt`; build the Docker image (no push) |
| `frontend` | PR, main, schedule | `npm ci`; `ng test --no-watch` (Vitest); `npm audit --audit-level=high`; build the Docker image (no push) |
| `publish` (matrix: 4 backends + frontend) | pushes to `main` only, after the two jobs above succeed | Assume the AWS role through OIDC; build; Trivy scan (fails on fixable HIGH/CRITICAL); push `app/<service>:<git sha>`; sign the image digest with cosign (keyless); write the digest to the job summary |

### How CI authenticates to AWS

No AWS keys are stored in GitHub. The `publish` job requests a short-lived OIDC token and assumes
`app-github-ecr-push`. The role trusts only this repository's `main` branch and can only push to
the five `app/*` ECR repositories. Pull requests and other branches cannot assume it.

### Things to know

* **Tags are immutable.** The image tag is the commit SHA. Re-running `publish` for a commit that
  was already published fails at the push step; push a new commit instead.
* **Failures are meaningful.** A Trivy or audit failure means a fixable HIGH/CRITICAL finding.
  Fix the dependency or base image rather than loosening the scan.
* **Pinned actions.** Third-party actions are pinned to version tags; check they still resolve
  when a job fails with "unable to resolve action".

## Deploying

The deployment is described by `deploy/envs/prod.yaml`; Argo CD applies whatever is on `main`.

### Release a new build

```bash
# 1. find the digest CI pushed for a commit (replace SHA)
for s in backend1 backend2 backend3 backend4 frontend; do
  echo -n "$s  "
  aws ecr describe-images --region us-east-1 --repository-name app/$s \
    --image-ids imageTag=<SHA> --query 'imageDetails[0].imageDigest' --output text
done

# 2. put the digests into deploy/envs/prod.yaml, then commit and merge to main
# 3. watch Argo CD roll it out
kubectl get applications -n argocd
kubectl rollout status deployment/backend1 -n app
```

### Roll back

Revert the commit that changed `deploy/envs/prod.yaml` (or restore the old digests) and merge it.
Argo CD applies it like any other change. The old images stay in ECR for as long as the lifecycle
policy keeps them.

### Verify an image was built by this pipeline

```bash
cosign verify \
  --certificate-identity-regexp 'https://github.com/akhilthekkuveettil/full-app-eks/.github/workflows/ci.yml@refs/heads/main' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  426737295553.dkr.ecr.us-east-1.amazonaws.com/app/backend1@sha256:<digest>
```

## Infrastructure changes

Infrastructure is changed with Terraform from a workstation (there is no pipeline for it yet).

```bash
cd infra/terraform/prod
terraform init -reconfigure     # once per checkout
terraform plan                  # read it; look for replace / destroy
terraform apply
```

* Work on a branch, commit the Terraform together with any `deploy/` change that depends on it,
  and merge after `apply` succeeded.
* Keep `terraform.tfvars` and state files out of git (already ignored).
* Changes to what runs in the cluster (chart, add-ons, image digests) go through `deploy/` and
  Argo CD, not through `kubectl apply`. Argo CD reverts manual changes (`selfHeal`).

## Local development

```bash
docker compose up -d --build     # postgres + 4 backends + frontend
# frontend: http://localhost:4200   backends: localhost:8001-8004
docker compose down
```

`DATABASE_URL` is required by the backends (no default); `docker-compose.yml` sets it for the
local Postgres.

Run the tests the same way CI does:

```bash
# backend (from backendN/)
pip install -r requirements.txt -r requirements-dev.txt
python -m pytest -q

# frontend (from frontend/)
npm ci
npx ng test --no-watch
```

## Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| `publish` fails: "Not authorized to perform sts:AssumeRoleWithWebIdentity" | Repository/branch or owner/repo IDs don't match the role trust | Check the subject in CloudTrail (`AssumeRoleWithWebIdentity` events) against `github_owner_id` / `github_repo_id` in `prod` |
| `publish` fails at push: "tag invalid: ... immutable" | The commit was already published | Push a new commit |
| Trivy step fails | Fixable HIGH/CRITICAL vulnerability in an image | Read the report; bump the base image digest or the dependency |
| Pods `CreateContainerConfigError` | `database` Secret not created yet | `kubectl describe externalsecret database -n app`; check the `app` Application sync result |
| Frontend returns 504 on `/api/...` | NetworkPolicy blocking ClusterIP traffic | Confirm `serviceCidr` matches the cluster's Service CIDR (`kubectl get svc kubernetes`) |
| `kubectl` times out | Your public IP is not in `api_allowed_cidrs` | Update `terraform.tfvars` and apply |
| Argo CD `app` stuck `Progressing` on a new cluster | First-sync race with the load balancer controller webhook | Terminate the sync operation and sync again |
