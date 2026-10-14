# Workflow

How a change moves from a commit to production, and how to work with the pieces along the way.
For what the infrastructure is, see [INFRASTRUCTURE.md](INFRASTRUCTURE.md).

## The path of a change

```
 feature branch / PR            main                                                 cluster
 -------------------            ----                                                 -------
 tests + dependency scan  --->  tests + scan + build  --->  terraform*  --->  publish  --->  bump PR   merge   Argo CD
 + image build (no push)        (same as PR)               plan/apply       push+sign       (digests) (deploy) syncs app
 + terraform plan (read-only)                              (gated)
 (* only when infra/ changed)
```

1. **Open a pull request.** CI runs tests, dependency scans and image builds, plus a read-only
   `terraform plan` when the PR touches `infra/`. Nothing is pushed or changed.
2. **Merge to `main`.** CI runs again. If the push touched `infra/` and the Terraform plan has
   changes, a person approves the apply first; otherwise Terraform is skipped. Then the `publish`
   job pushes signed images to ECR.
3. **A digest-bump pull request opens automatically** (`bump-digests` job). It points
   `deploy/envs/prod.yaml` at the images that were just published, after verifying their cosign
   signatures.
4. **Merge that pull request to deploy.** Argo CD syncs `deploy/` from `main` to the cluster.

## CI: `.github/workflows/ci.yml`

Triggers: pull requests, pushes to `main`, and a weekly schedule (Mondays 06:00 UTC) so newly
published vulnerabilities are caught even without a push. A new push to the same ref cancels
the older run.

| Job | Runs for | What it does |
|---|---|---|
| `backend` (matrix: backend1-4) | PR, main, schedule | Install pinned, hash-checked dependencies; `pytest`; `pip-audit` against `requirements.txt`; build the Docker image (no push) |
| `frontend` | PR, main, schedule | `npm ci`; `ng test --no-watch` (Vitest); `npm audit --audit-level=high`; build the Docker image (no push) |
| `changes` | PR, main, schedule | Looks at the files changed in the push or pull request and sets `infra=true` only if something under `infra/` changed (a new branch or force-push counts as changed; scheduled runs do not) |
| `terraform-plan` | only when `infra/` changed | `terraform fmt -check`, `init`, `validate`, `plan` against production with the read-only role `app-github-terraform-plan`; the plan is written to the job summary. On `main`, a plan with changes is kept as an artifact for the apply job |
| `terraform-apply` | pushes to `main` when `infra/` changed and the plan has changes | Runs in the `production-infra` environment (required reviewers), assumes `app-github-terraform-apply`, and applies exactly the saved plan. Skipped when there is nothing to change |
| `publish` (matrix: 4 backends + frontend) | pushes to `main` only, after tests, scans and the Terraform step succeed (an apply that was skipped for "no changes" counts as success) | Assume the AWS role through OIDC; build; Trivy scan (fails on fixable HIGH/CRITICAL); push `app/<service>:<git sha>`; sign the image digest with cosign (keyless); write the digest to the job summary |
| `bump-digests` | after `publish` succeeds | Look up the digest of each image tagged with the commit SHA; `cosign verify` that this workflow signed it; rewrite the digests in `deploy/envs/prod.yaml` (`.github/scripts/bump_digests.py`); push branch `automation/bump-digests` and open or update a single pull request |

### How CI authenticates to AWS

No AWS keys are stored in GitHub. The `publish` job requests a short-lived OIDC token and assumes
`app-github-ecr-push`. The role trusts only this repository's `main` branch and can only push to
the five `app/*` ECR repositories. Pull requests and other branches cannot assume it.

### Things to know

* **Tags are immutable.** The image tag is the commit SHA. Re-running `publish` for a commit that
  was already published fails at the push step; push a new commit instead.
* **Failures are meaningful.** A Trivy or audit failure means a fixable HIGH/CRITICAL finding.
  Fix the dependency or base image rather than loosening the scan.
* **Pushes that only touch `deploy/` or Markdown skip CI** (`paths-ignore`). This is what stops the
  merged bump PR from publishing new images and opening another bump PR.
* **One rolling PR.** `automation/bump-digests` is force-updated, so there is never more than one
  open bump PR; it always reflects the newest published commit.
* **Repository setting required:** Settings -> Actions -> General -> "Allow GitHub Actions to
  create and approve pull requests". Pull requests opened with the built-in token do not trigger
  other workflows, which is fine here because only `deploy/envs/prod.yaml` changes.
* **Pinned actions.** Third-party actions are pinned to version tags; check they still resolve
  when a job fails with "unable to resolve action".

## Deploying

The deployment is described by `deploy/envs/prod.yaml`; Argo CD applies whatever is on `main`.

### Release a new build

Normally there is nothing to do except review and merge the bump PR that CI opens. The manual
equivalent, for example when CI is unavailable:

```bash
# 1. find the digest CI pushed for a commit (replace SHA)
for s in backend1 backend2 backend3 backend4 frontend; do
  echo -n "$s  "
  aws ecr describe-images --region us-east-1 --repository-name app/$s \
    --image-ids imageTag=<SHA> --query 'imageDetails[0].imageDigest' --output text
done

# 2. write them into deploy/envs/prod.yaml, then commit and merge to main
python3 .github/scripts/bump_digests.py deploy/envs/prod.yaml \
  backend1=sha256:... backend2=sha256:... backend3=sha256:... backend4=sha256:... frontend=sha256:...
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

Infrastructure changes go through the same pipeline: the PR shows the plan in the job summary,
and after merge the apply runs once someone approves the `production-infra` environment. The
infrastructure step always runs before images are published and deployed.

### One-time setup for the pipeline

1. Create the two CI roles by applying Terraform locally once (they cannot create themselves):
   `cd infra/terraform/prod && terraform init -reconfigure && terraform apply`.
2. GitHub: Settings -> Environments -> New environment `production-infra`; add required
   reviewers and restrict "Deployment branches" to `main`.
3. GitHub: Settings -> Secrets and variables -> Actions -> New repository secret
   `TF_API_ALLOWED_CIDRS` with a JSON list, e.g. `["203.0.113.7/32"]` (the CIDRs allowed to reach
   the Kubernetes API; the value that is in your local `terraform.tfvars`).
4. Only then merge the workflow change, otherwise the Terraform jobs cannot assume their roles.

### Local changes (when you need them)

```bash
cd infra/terraform/prod
terraform init -reconfigure     # once per checkout
terraform plan                  # read it; look for replace / destroy
terraform apply
```

* Prefer the pipeline. Local `apply` is for bootstrapping and emergencies; if you do apply
  locally, merge the same code so the next CI plan shows no changes.
* Work on a branch and commit the Terraform together with any `deploy/` change that depends on it.
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
| `bump-digests` fails: "GitHub Actions is not permitted to create or approve pull requests" | Repository setting is off | Enable it under Settings -> Actions -> General |
| `bump-digests` fails at `cosign verify` | An image for that commit was not signed by this workflow | Check the `publish` run for that commit; do not deploy the image |
| Trivy step fails | Fixable HIGH/CRITICAL vulnerability in an image | Read the report; bump the base image digest or the dependency |
| Pods `CreateContainerConfigError` | `database` Secret not created yet | `kubectl describe externalsecret database -n app`; check the `app` Application sync result |
| Frontend returns 504 on `/api/...` | NetworkPolicy blocking ClusterIP traffic | Confirm `serviceCidr` matches the cluster's Service CIDR (`kubectl get svc kubernetes`) |
| `terraform-plan` fails to assume its role | The CI roles do not exist yet, or the OIDC subject does not match | Apply Terraform locally once (see "One-time setup"); check `github_owner_id` / `github_repo_id` |
| `terraform-apply` waits forever | The `production-infra` environment needs a reviewer to approve | Approve the deployment in the Actions run |
| Plan wants to change something unexpected | Local `apply` or a console change drifted from the code | Read the plan; fix the code or revert the drift, do not approve blindly |
| `kubectl` times out | Your public IP is not in `api_allowed_cidrs` | Update `terraform.tfvars` and apply |
| Argo CD `app` stuck `Progressing` on a new cluster | First-sync race with the load balancer controller webhook | Terminate the sync operation and sync again |
