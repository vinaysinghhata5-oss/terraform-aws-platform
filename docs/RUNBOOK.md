# Runbook: set up, operate and tear down the platform

Every step, in order, from an empty AWS account to a working EKS cluster managed by GitHub Actions.

```
 Phase 0  Tools on your laptop
 Phase 1  Bootstrap the AWS account   (once, admin credentials)   → state bucket, KMS, OIDC, CI roles, people, budget
 Phase 2  Configure GitHub            (once)                      → variables, secret, environments, branch protection
 Phase 3  First deploy                (local script OR pipeline)  → VPC, EKS 1.35, node group, bastion
 Phase 4  Day-to-day changes          (PR → plan → merge → apply)
 Phase 5  Access the cluster          (people: MFA role + SSM tunnel)
 Phase 6  Save cost / tear down       (destroy workflow)
```

---

## Phase 0: tools

```bash
brew install terraform awscli kubectl gh jq
brew install --cask session-manager-plugin      # needed for SSM tunnels/sessions
gh auth login                                   # GitHub CLI
```

| Tool | Version used |
|---|---|
| Terraform | 1.16.5 (`.terraform-version`) |
| AWS provider | 6.x (locked in `.terraform.lock.hcl`) |
| EKS / kubectl | 1.35 |

---

## Phase 1: bootstrap the AWS account (once per account)

**Why a separate bootstrap?** The pipeline authenticates with OIDC roles and stores state in S3, but
those must exist *before* the pipeline can run (chicken and egg). Bootstrap is the only step that uses
admin credentials.

1. Edit `bootstrap/dev.tfvars` (GitHub org/repo, numeric IDs, people):
   ```hcl
   github_org      = "vinaysinghhata5-oss"
   github_repo     = "terraform-aws-platform"
   github_owner_id = "234816913"     # gh api users/<owner> --jq .id
   github_repo_id  = "1406873367"    # gh api repos/<owner>/<repo> --jq .id
   admin_users     = ["vinay"]
   developer_users = ["amar-dev"]
   ```
2. Run with admin credentials (an SSO session, or a temporary admin key):
   ```bash
   AWS_PROFILE=<admin> BUDGET_EMAIL=<you@example.com> ./scripts/bootstrap.sh dev
   ```
   First run: applies with local state, then **migrates its own state into the bucket it just created**.
   Later runs: work directly against S3.

**Creates:** S3 state bucket (KMS, versioned, TLS-only), KMS key `alias/terraform-state`, GitHub OIDC
provider, `gha-terraform-plan-dev` and `gha-terraform-apply-dev` roles, users/groups/roles for people,
password policy, and a $20/month budget alert.

---

## Phase 2: configure GitHub (once)

| Setting | Value | Where |
|---|---|---|
| Variable `AWS_REGION` | `us-east-1` | Settings → Secrets and variables → Actions → Variables |
| Variable `DEV_AWS_ACCOUNT_ID` | your account ID | same |
| Variable `DEV_EKS_ADMIN_PRINCIPAL_ARNS` | `[]` or a JSON list of break-glass ARNs | same |
| Variable `DEPLOY_ENABLED` | `true` (`false` pauses all deploys) | same |
| Secret `TF_PLAN_ENCRYPTION_KEY` | `openssl rand -base64 32` | Secrets |
| Environment `dev` | deploy from `main` only, no reviewers | Settings → Environments |
| Environments `qa`, `prod` | required reviewer; prod 5-min wait timer; `main` only | same |
| Branch protection `main` | PR required; checks `fmt / validate / tflint`, `checkov (IaC security)`, `plan (dev)`; no force push | Settings → Branches |

CLI equivalents:
```bash
gh variable set AWS_REGION --body us-east-1
gh variable set DEV_AWS_ACCOUNT_ID --body <account-id>
gh variable set DEPLOY_ENABLED --body true
gh secret set TF_PLAN_ENCRYPTION_KEY --body "$(openssl rand -base64 32)"
```

**Important:** create `qa`/`prod` environments with protection **before** any workflow references them.
GitHub auto-creates missing environments **without** protection.

---

## Phase 3: first deploy

**Option A: pipeline (normal):** Actions → **terraform-deploy** → Run workflow.

**Option B: from a laptop (first time / break-glass):**
```bash
AWS_PROFILE=<admin> BUDGET_EMAIL=<you@example.com> ./scripts/dev-up.sh
```
It runs bootstrap → init → plan → asks `yes` → apply → checks `kubectl get nodes` on the bastion.
Takes about 20 minutes (the EKS control plane takes about 11).

Expected result:
```
NAME                         STATUS   VERSION
ip-10-10-x-x.ec2.internal    Ready    v1.35.x-eks-…
kube-system  aws-node, coredns x2, ebs-csi-controller x2, ebs-csi-node, eks-pod-identity-agent, kube-proxy  Running
```

---

## Phase 4: day-to-day changes (GitOps flow)

```
git checkout -b feat/x  →  edit  →  push  →  open PR
   CI: fmt · validate · tflint · checkov · plan (per env)
   bot comment:  dev: ➕ 0 to add · 🔄 1 to change · ♻️ 0 to replace · 🗑️ 0 to destroy
   ⚠️ warning if anything is destroyed/replaced
review → merge
   terraform-deploy: dev plan → apply automatically
                     qa  plan → ⏸ approval → apply
                     prod plan → ⏸ approval + 5 min → apply
```

Rules:
- **Every merge to `main` deploys.** To merge without deploying: `gh variable set DEPLOY_ENABLED --body false`.
- Apply uses the **saved, encrypted plan** from the plan job; if state changed in between, Terraform refuses (stale plan).
- **Read the summary line before merging.** A large ➕ or any 🗑️ that you didn't expect means stop.

Nightly **terraform-drift** opens a GitHub issue (label `drift`) if AWS differs from the code.

---

## Phase 5: access the cluster

See [HUMAN_ACCESS.md](HUMAN_ACCESS.md) for onboarding (console password → MFA → own access key → CLI profile).

```bash
AWS_PROFILE=vinay-admin ./scripts/eks-tunnel.sh       # terminal 1: tunnel stays open
kubectl get nodes                                      # terminal 2: runs as YOUR role
kubectl auth can-i --list
```

Admin shell on the bastion (recorded): EC2 console → instance `acme-dev-bastion` → Connect → Session Manager.
Session logs: CloudWatch → `/aws/ssm/sessions/acme-dev`.

---

## Phase 6: save cost / tear down

| Action | How | Time |
|---|---|---|
| Stop paying for dev | Actions → **terraform-destroy** → env `dev`, confirm `dev` | about 10 min |
| Bring dev back | Actions → **terraform-deploy** → Run workflow | about 20 min |
| Pause all deploys | `gh variable set DEPLOY_ENABLED --body false` | instant |

Dev costs about **$0.27/hour** (EKS $0.10 + NAT $0.05 + 2 small EC2 + extras). Bootstrap resources
(state bucket, roles, budget) stay and cost about $1/month.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity` | Trust policy `sub` doesn't match the token (immutable subject, wrong branch/environment) | `gh api repos/<o>/<r>/actions/oidc/customization/sub`; set `github_owner_id`/`github_repo_id`; re-run bootstrap |
| `AWS account ID not allowed` | Wrong account or placeholder account ID won | Check `DEV_AWS_ACCOUNT_ID`; CI writes `ci.auto.tfvars.json` |
| `Error acquiring the state lock` | Another run holds the lock, or a run crashed | Wait (`-lock-timeout=5m`); if crashed: `terraform force-unlock <ID>` after confirming nothing is running |
| `Saved plan is stale` | State changed between plan and apply | Re-run the deploy workflow |
| Plan shows everything as ➕ add | Environment was destroyed, or wrong state bucket/key | Check terraform-destroy runs; check `backend-config` bucket |
| Bastion: `kubectl: command not found` | User data failed (e.g. no network at boot) | `/var/log/bastion-setup.log`; re-create the instance |
| kubectl `Unauthorized` / `Forbidden` | No access entry for your role, or view-only role | `aws sts get-caller-identity`; check `eks_*_role_names` |
| Tunnel: `TargetNotConnected` | Bastion stopped, or SSM agent has no route | Check the instance is running and the NAT gateway exists |
