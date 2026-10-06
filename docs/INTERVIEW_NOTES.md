# Interview notes – walk through this repo like a senior engineer

## 60-second pitch

"Each environment is a separate root module with its own S3 backend, **in its own AWS account**.
The code is identical; only tfvars differ, so the same change is promoted dev → qa → prod.
CI has no static keys – GitHub OIDC assumes a read-only role for PR plans and a separate apply role
that can only be assumed by a job inside an approved GitHub Environment. We apply the exact saved plan
that was reviewed, scan IaC with tflint and Checkov on every PR, and run nightly drift detection."

## Likely questions & strong answers

**Q: How do you manage multiple environments?**
Directory-per-env roots calling shared modules. Separate state + separate accounts = minimal blast radius.
Workspaces share backend and credentials, so I only use them for ephemeral copies of the same env
(e.g. per-PR preview stacks).

**Q: How is state secured and locked?**
S3 with SSE-KMS (CMK), versioning, TLS-only bucket policy, public access block. Since Terraform 1.10
the S3 backend supports native locking via a `.tflock` object (`use_lockfile = true`), so DynamoDB is no
longer required. The plan role can only write `*.tflock`, never the state itself.

**Q: State got corrupted / someone deleted a resource. What do you do?**
Restore a previous state version from S3 versioning. For drift: `terraform plan -refresh-only`,
then `terraform import` (or an `import {}` block) or `terraform state rm`. Use `moved {}` blocks for
refactors instead of manual `state mv`, so it is reviewable in a PR.

**Q: How do GitHub Actions authenticate to AWS?**
OIDC. GitHub issues a signed JWT; AWS IAM trusts `token.actions.githubusercontent.com`. Trust policy
checks `aud = sts.amazonaws.com` and `sub`. The `sub` is the key control:
`repo:org/repo:pull_request` → plan role; `repo:org/repo:environment:prod` → apply role.
Credentials last ≤ 1 hour and nothing is stored in GitHub secrets.

**Q: How do you stop someone merging straight to prod?**
Branch protection + CODEOWNERS (security team owns `envs/prod`), required status checks,
GitHub Environment `prod` with required reviewers, prevent self-review, wait timer, `main`-only
deployment branches. Even with stolen PR access, the apply role's trust policy only accepts the
`environment:prod` subject.

**Q: Why apply a saved plan?**
What was reviewed is exactly what runs. If someone else changed state in between, Terraform rejects
the stale plan. Plans can contain secrets, so the artifact is encrypted and kept for 1 day.

**Q: How do you handle secrets?**
Never in tfvars or code. RDS `manage_master_user_password = true` → RDS generates & rotates the password
in Secrets Manager, so it is never in state. Apps read it at runtime via an IAM role scoped to that one
secret ARN. Sensitive outputs use `sensitive = true`. gitleaks in pre-commit.

**Q: How do you prevent destroying production data?**
`deletion_protection`, final snapshots, S3 versioning, KMS 30-day deletion window, `prevent_destroy`
lifecycle (add on prod-only critical resources), PR review of plan for `-/+ replace` and `destroy` lines,
and an apply role that cannot touch the state bucket.

**Q: Supply-chain security for Terraform and Actions?**
Commit `.terraform.lock.hcl` and run `init -lockfile=readonly`; pin provider versions; pin actions to
commit SHAs; Dependabot updates; harden-runner egress audit; least-privilege `permissions:` per job.

**Q: How do you detect drift?**
Scheduled `plan -detailed-exitcode` (exit 2 = changes) with the read-only role; opens a GitHub issue.
Root cause is usually console changes → fix by removing console write access (SSO read-only in prod).

**Q: Module design principles?**
Small, single-purpose; no provider or backend blocks inside modules; typed + validated + documented
variables; secure defaults (encryption on, public off); outputs for composition; version with git tags.

**Q: How would you scale this to 50 teams / 200 accounts?**
Terragrunt or Terraform Stacks to DRY backends; account vending (Control Tower / AFT); private module
registry; policy-as-code (OPA/Sentinel) on plans; Atlantis or TFC/Spacelift for PR automation.

## EKS questions

**Q: How do users and CI authenticate to the cluster?**
EKS access entries (`authentication_mode = "API"`) map IAM principals to access policies
(`AmazonEKSClusterAdminPolicy`, `AmazonEKSViewPolicy`). No `aws-auth` ConfigMap to break, and
`bootstrap_cluster_creator_admin_permissions = false` so the Terraform role isn't a hidden admin.

**Q: IRSA vs Pod Identity?**
Both give pods scoped AWS credentials. Pod Identity needs no per-cluster OIDC provider, the trust policy
is the same for every cluster (`pods.eks.amazonaws.com`), and the SA→role mapping is an EKS API object.
IRSA is still needed for a few add-ons/Fargate; know both.

**Q: Why hop limit 1 on nodes?**
With IMDSv2 hop limit 1, a container (one extra network hop) can't reach the instance metadata service,
so a compromised pod can't use the node role. Pods get AWS access only via Pod Identity.

**Q: How do you upgrade EKS (e.g. 1.35 → 1.36)?**
One minor version at a time. Check deprecated APIs (`kubectl convert`, Pluto, EKS upgrade insights),
upgrade dev first: bump `eks_version` → control plane upgrades, then node groups roll (same version
variable) respecting PodDisruptionBudgets, then add-ons (data source picks the newest compatible).
Promote to qa/prod through the same pipeline. EKS allows rolling the control plane back within 7 days.

**Q: Why no Kubernetes/Helm provider in Terraform?**
Mixing them couples cluster creation with in-cluster state, needs API network access from CI (prod is
private), and causes ordering/auth problems on create/destroy. Terraform builds the platform;
Argo CD/Flux deploys what runs on it.

**Q: Why two node groups in prod?**
A small, tainted on-demand `system` group (CriticalAddonsOnly) keeps CoreDNS/controllers away from noisy
application pods; the `general` group scales for workloads. Next step: Karpenter for bin-packing and Spot.

## Commands you should know cold

```bash
terraform plan -detailed-exitcode     # 0 none, 1 error, 2 changes
terraform plan -refresh-only          # see drift without proposing config changes
terraform apply tfplan                # apply a saved plan
terraform state list | show | mv | rm
terraform import / import {} block    # adopt existing resources
terraform force-unlock <LOCK_ID>      # only after confirming no run is active
terraform providers lock -platform=linux_amd64 -platform=darwin_arm64
terraform console                     # test expressions like cidrsubnet()
terraform test                        # native module tests (.tftest.hcl)
```
