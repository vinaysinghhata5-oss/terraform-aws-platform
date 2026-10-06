# terraform-aws-platform

Production-grade, multi-environment (**dev / qa / prod**) AWS infrastructure with Terraform,
GitHub Actions CI/CD, and security controls at every layer.

```
                     Internet
                        │
                ┌───────▼────────┐  HTTPS (TLS 1.3 policy), WAF, access logs
                │  ALB (public)  │
                └───────┬────────┘
     ┌──────────────────┼──────────────────┐   private subnets, no public IPs,
     │  ASG: EC2 (IMDSv2, encrypted EBS,   │   no SSH - access via SSM only
     │  SSM, least-privilege role)         │
     └──────────────────┬──────────────────┘
                        │ 5432 (SG → SG only, TLS forced)
                ┌───────▼────────┐  isolated subnets, no internet route,
                │ RDS PostgreSQL │  KMS encrypted, password in Secrets Manager
                └────────────────┘
```

## Repository layout

```
.
├── bootstrap/                # One-time per account: state bucket, KMS, GitHub OIDC + CI roles
├── modules/                  # Reusable, versioned building blocks (no provider/backends inside)
│   ├── kms/                  #   CMK with rotation + scoped key policy
│   ├── vpc/                  #   3-tier subnets, NAT, flow logs, S3 endpoint, default-deny SG
│   ├── s3-bucket/            #   Private, versioned, encrypted, TLS-only bucket
│   ├── alb/                  #   ALB, HTTPS redirect, drop invalid headers, WAF hook
│   ├── app-asg/              #   Launch template (IMDSv2) + ASG + target tracking
│   ├── eks/                  #   EKS 1.35, access entries, Pod Identity, managed add-ons, node groups
│   └── rds/                  #   PostgreSQL, Multi-AZ, managed secret, force SSL
├── envs/
│   ├── dev/                  # Root module per env: own backend, own state, own AWS account
│   ├── qa/
│   └── prod/
├── templates/user_data.sh
├── .github/
│   ├── workflows/
│   │   ├── terraform-ci.yml      # PR: fmt, validate, tflint, checkov, plan x3 envs + PR comment
│   │   ├── terraform-deploy.yml  # main: dev → qa → prod promotion
│   │   ├── _terraform-apply.yml  # reusable: plan → (approval) → apply saved plan
│   │   └── terraform-drift.yml   # nightly drift detection → GitHub issue
│   ├── CODEOWNERS
│   ├── dependabot.yml
│   └── pull_request_template.md
├── .checkov.yaml  .tflint.hcl  .pre-commit-config.yaml  .terraform-version  Makefile
└── docs/INTERVIEW_NOTES.md   # Design decisions & Q&A for interviews
```

### Why directories per environment (not workspaces)?

| | Directory per env (used here) | Terraform workspaces |
|---|---|---|
| State isolation | Separate backend **in a separate account** | Same backend, different key |
| Blast radius | A mistake in dev can't touch prod creds | Same credentials for all envs |
| Env-specific config | Explicit `terraform.tfvars` per env | `terraform.workspace` conditionals |
| Visibility in PR | Diff clearly shows which env changes | Hidden in runtime state |

`main.tf` is identical across envs; **only `terraform.tfvars` and `backend.tf` differ**. Promotion =
the same code moving through dev → qa → prod.

## Environment differences

| Setting | dev | qa | prod |
|---|---|---|---|
| AWS account | 111111111111 | 222222222222 | 333333333333 |
| VPC CIDR | 10.10.0.0/16 | 10.20.0.0/16 | 10.30.0.0/16 |
| AZs / NAT | 2 / single NAT | 2 / single NAT | 3 / NAT per AZ (HA) |
| App instances | t3.micro, 1-2 | t3.small, 1-3 | m6i.large, 3-10 |
| RDS | db.t4g.micro, single-AZ, 1d backup | db.t4g.small, 7d | db.m6g.large, **Multi-AZ**, 35d |
| EKS (v1.35) API endpoint | public, office CIDR | public, office CIDR | **private only** (VPN) |
| EKS nodes | Spot, 1-4 (mixed types) | on-demand m6i.large, 2-5 | `system` (tainted) 3-6 + `general` 3-15 |
| VPC interface endpoints | none (NAT) | ECR, STS | ECR, STS, EC2, Logs, SSM |
| EKS zonal shift | off | off | on |
| Deletion protection | off | on | on |
| Log retention | 30d | 90d | 365d |
| ALB ingress | office/VPN CIDR | office/VPN CIDR | public, HTTPS + WAF |
| Deploy gate | auto | required reviewer | required reviewers + wait timer |

## Security controls

**Identity & CI/CD**
- **No static AWS keys anywhere.** GitHub Actions authenticates via **OIDC** → `sts:AssumeRoleWithWebIdentity`.
- **Two roles per account:** `gha-terraform-plan-<env>` (ReadOnly, usable from PRs) and
  `gha-terraform-apply-<env>` (trusts *only* `repo:<org>/<repo>:environment:<env>`, so it can only be
  assumed by a job that passed that GitHub Environment's approval gate).
- Apply role has an **explicit-deny guardrail** policy: can't edit CI roles, the OIDC provider, the
  state bucket/key, create IAM users/access keys, or touch Organizations.
- Plan role is explicitly denied `secretsmanager:GetSecretValue`.
- `allowed_account_ids` in every provider → Terraform refuses to run against the wrong account.
- Workflows use `permissions: contents: read` by default; jobs opt in to `id-token: write`.
- Fork PRs never get an OIDC token → can't reach AWS. `pull_request_target` is never used.
- Saved plan is **encrypted** before upload as an artifact (plans may contain secrets), 1-day retention.
- **Apply the exact reviewed plan** (`terraform apply tfplan`) – stale plans are rejected.
- `concurrency` groups per env: no two runs touch the same state at once; never cancels an apply.
- `step-security/harden-runner` audits runner egress; `persist-credentials: false` on checkout.
- CODEOWNERS + branch protection; Dependabot for actions & providers; committed `.terraform.lock.hcl`
  and `init -lockfile=readonly` (provider supply-chain pinning).

**State**
- S3 backend, SSE-KMS, versioning (365 days of history for rollback), TLS-only, public access blocked.
- **S3 native locking** (`use_lockfile = true`, Terraform ≥ 1.10) – no DynamoDB table needed.
- One state file per env, in that env's account.

**Infrastructure**
- Network: 3 tiers; DB subnets have **no route to the internet**; default SG denies all; VPC flow logs
  (KMS-encrypted); S3 gateway endpoint.
- Compute: **IMDSv2 required** (hop limit 1), encrypted EBS, **no SSH / no key pairs** (SSM Session Manager),
  instance role scoped to one secret + one key, SG ingress only from ALB SG.
- Data: RDS encrypted with CMK, `publicly_accessible = false`, `rds.force_ssl = 1`, IAM DB auth,
  **master password generated & rotated by RDS in Secrets Manager** (never in code or state),
  deletion protection + final snapshot, Performance Insights encrypted.
- Edge: HTTP→HTTPS redirect, `ELBSecurityPolicy-TLS13-1-2-2021-06`, `drop_invalid_header_fields`,
  access logs, optional WAFv2.
- Encryption: customer-managed KMS keys with automatic rotation.

**EKS (Kubernetes 1.35)**
- **Access entries** (`authentication_mode = "API"`) instead of the `aws-auth` ConfigMap; the cluster
  creator gets **no** implicit admin – every admin/read-only principal is declared in tfvars and reviewed.
- Kubernetes **Secrets envelope-encrypted** with the CMK; all 5 control-plane log types to a KMS-encrypted log group.
- API endpoint: private in prod; in dev/qa public but CIDR-restricted (`0.0.0.0/0` rejected by validation).
- **EKS Pod Identity** for add-ons (vpc-cni, EBS CSI) – AWS permissions live on the service account,
  not the node role. Node role is minimal: worker policy, ECR **pull-only**, SSM.
- Nodes: AL2023, IMDSv2 with **hop limit 1** (pods can't steal node credentials), KMS-encrypted gp3,
  no SSH, automatic **node repair**, rolling updates (33% max unavailable), Spot diversification in dev.
- Managed add-ons with explicit ordering (pod-identity-agent, vpc-cni, kube-proxy **before** nodes;
  CoreDNS, EBS CSI **after**), VPC CNI **NetworkPolicy enforcement** + prefix delegation.
- `upgrade_policy = STANDARD` (no surprise extended-support charges), `deletion_protection`, ARC zonal shift in prod.
- Terraform only talks to AWS APIs (no `kubernetes`/`helm` provider), so CI never needs network
  access to a private API server. In-cluster apps/controllers belong in GitOps (Argo CD / Flux).

  ```bash
  aws eks update-kubeconfig --name acme-dev --region us-east-1   # after `terraform apply`
  ```

**Shift-left scanning** – `terraform fmt`, `validate`, `tflint` (+AWS ruleset), `checkov` (SARIF → GitHub
Security tab), `gitleaks` and pre-commit hooks locally. Any Checkov exception is an inline
`#checkov:skip=ID:reason` so it's reviewed in the PR.

## CI/CD flow

```
feature branch ──PR──► terraform-ci
                        ├─ fmt / validate / tflint
                        ├─ checkov ─► Security tab
                        └─ plan dev | qa | prod (read-only role) ─► PR comments
merge to main ───────► terraform-deploy
                        ├─ dev : plan ─► apply (auto)
                        ├─ qa  : plan ─► ⏸ approval ─► apply
                        └─ prod: plan ─► ⏸ approval (+wait timer) ─► apply
nightly ─────────────► terraform-drift ─► opens "drift" issue if infra ≠ code
```

## Setup

1. **Bootstrap each account** (once, with admin SSO credentials for that account):
   ```bash
   # edit bootstrap/<env>.tfvars (account id, github org/repo)
   AWS_PROFILE=acme-dev  make bootstrap ENV=dev
   AWS_PROFILE=acme-qa   make bootstrap ENV=qa
   AWS_PROFILE=acme-prod make bootstrap ENV=prod
   ```
   Then uncomment the backend in `bootstrap/versions.tf` and `terraform init -migrate-state`.
2. **Update placeholders**: account IDs in `envs/*/terraform.tfvars` and bucket names in
   `envs/*/backend.tf`, ACM cert and WAF ARNs for prod, CIDRs, `@your-org/*` in CODEOWNERS.
3. **Generate and commit provider lock files**: `make lock` (CI uses `-lockfile=readonly`).
4. **GitHub settings**
   - *Variables* (repo): `DEPLOY_ENABLED=true` (plans/deploys/drift are skipped until set), `AWS_REGION`, `DEV_AWS_ACCOUNT_ID`, `QA_AWS_ACCOUNT_ID`, `PROD_AWS_ACCOUNT_ID`.
   - *Secret* (repo): `TF_PLAN_ENCRYPTION_KEY` (`openssl rand -base64 32`).
   - *Environments*: `dev`, `qa`, `prod` – deployment branches = `main` only;
     `qa` 1 required reviewer; `prod` 2 required reviewers, prevent self-review, wait timer.
   - *Branch protection on `main`*: require PR, CODEOWNERS review, status checks
     (`fmt / validate / tflint`, `checkov`, `plan (*)`), signed commits, no force push.
   - Settings → Actions: allow only selected/verified actions; default `GITHUB_TOKEN` read-only.
5. **Pin actions to commit SHAs** before real use (e.g. `pinact run` or `ratchet`). Tags are used here
   for readability; SHA-pinning protects against a compromised/re-tagged action
   (cf. the 2025 `tj-actions/changed-files` incident). Dependabot keeps the SHAs updated.

## Run it from GitHub Actions

| Workflow | Trigger | What it does |
|---|---|---|
| `bootstrap` | manual, once per account | State bucket, KMS, OIDC roles, budget. Only workflow using static keys (`BOOTSTRAP_AWS_*` secrets) - delete them afterwards |
| `terraform-ci` | pull request | fmt, validate, tflint, Checkov, plan for each configured env, plan as PR comment |
| `terraform-deploy` | push to `main` / manual | dev → qa → prod; envs without an account variable are skipped |
| `terraform-destroy` | manual (type env name to confirm) | Tear down dev/qa after practice |
| `terraform-drift` | nightly | Opens an issue when AWS differs from code |

Repository settings used (Settings → Secrets and variables → Actions):

| Name | Kind | Example |
|---|---|---|
| `DEPLOY_ENABLED` | variable | `true` |
| `AWS_REGION` | variable | `us-east-1` |
| `DEV_AWS_ACCOUNT_ID` | variable | `123456789012` (same for `QA_`/`PROD_`) |
| `DEV_EKS_ADMIN_PRINCIPAL_ARNS` | variable | `["arn:aws:iam::123456789012:user/dev"]` |
| `TF_PLAN_ENCRYPTION_KEY` | secret | `openssl rand -base64 32` |
| `BUDGET_EMAIL` | secret | used by `bootstrap` only |

Run manually: **Actions → terraform-deploy → Run workflow**, or `gh workflow run terraform-deploy`.
Tear down: **Actions → terraform-destroy → Run workflow** (environment `dev`, confirm `dev`).

Locally instead: `AWS_PROFILE=dev ./scripts/dev-up.sh` and `./scripts/dev-down.sh`.

## Local usage

```bash
pre-commit install
make fmt validate lint scan
AWS_PROFILE=acme-dev make plan ENV=dev
```

## Production hardening not included (talk about these!)

- AWS Organizations **SCPs** duplicating the guardrails (deny leaving org, disabling CloudTrail/GuardDuty, non-approved regions).
- Org-level CloudTrail, GuardDuty, Security Hub, AWS Config in a dedicated security/log-archive account.
- Scoped apply policy + **permissions boundary** instead of `AdministratorAccess`.
- Module versioning via git tags (`?ref=v1.2.0`) or a private registry once modules are shared across repos.
- Policy-as-code gates on the plan (OPA/Conftest, Sentinel) – e.g. "no public S3", "prod must be Multi-AZ".
- Cost estimation in PRs (Infracost); Terratest for module tests (or `terraform test`).
- EKS: Karpenter (or EKS Auto Mode) for node autoscaling, Argo CD for GitOps, AWS Load Balancer
  Controller, ExternalDNS, External Secrets, Kyverno/Gatekeeper policies, GuardDuty EKS runtime monitoring.
