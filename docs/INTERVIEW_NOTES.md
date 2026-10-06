# Interview guide: presenting this project as a Senior DevOps Engineer

Contents:
1. [How to frame it honestly](#1-how-to-frame-it-honestly)
2. [30-second pitch](#2-the-30-second-pitch)
3. ["Tell me about your project" (2-minute answer)](#3-tell-me-about-your-project-2-minute-answer)
4. [5-minute architecture walkthrough](#4-the-5-minute-architecture-walkthrough)
5. [Deep dives by topic](#5-deep-dives-by-topic)
6. [Issues we faced and how we fixed them](#6-issues-we-faced-and-how-we-fixed-them) ← the most valuable section
7. [Question bank with model answers](#7-question-bank-with-model-answers)
8. [Trade-offs and what I'd do at company scale](#8-trade-offs-and-what-id-do-at-company-scale)
9. [Commands to know cold](#9-commands-to-know-cold)

---

## 1. How to frame it honestly

- Call it a **personal platform project you designed, deployed and operated** to practise production patterns.
- **Don't claim** it served real customers or a real team. Follow-up questions about users, incidents or
  team size expose that quickly, and honesty about scope is respected.
- What interviewers want from a senior engineer is **decisions, trade-offs, debugging and ownership**.
  Sections 5–8 give you exactly that.
- Answer structure: **Context → What I built → Key decisions (why) → Challenges → Results → Improvements.**
- Speak in short sentences, draw the diagram, and **stop after about 2 minutes** so they can ask questions.

---

## 2. The 30-second pitch

> "I built a production-style AWS platform with Terraform: dev, qa and prod environments and an EKS 1.35
> cluster. Each environment has its own state and is designed for its own AWS account, and the same code is
> promoted dev to qa to prod. CI/CD runs on GitHub Actions with **OIDC, so there are no AWS keys in GitHub**.
> Every PR shows a plan summary per environment. Merging auto-deploys dev, and qa and prod need approval.
> The EKS API is private and reached through an SSM bastion, people log in through MFA-protected roles,
> and security scanning runs on every change."

---

## 3. "Tell me about your project" (2-minute answer)

> **Context.** "I wanted to build a Kubernetes platform the way a real company would run it, not a demo:
> secure by default, separate environments, and fully automated through CI/CD with no stored cloud keys."
>
> **What I built.** "It's Terraform on AWS: reusable modules for the VPC, KMS, EKS, RDS, ALB and a bastion,
> plus one folder per environment. The core is an EKS 1.35 cluster with a **private API endpoint**. There's
> no SSH anywhere; access goes through AWS Systems Manager."
>
> **Key decisions.**
> "First, **no long-lived credentials**. The pipeline uses GitHub OIDC with two roles: a read-only plan role
> for pull requests, and an apply role that only trusts a job running inside an approved GitHub Environment.
> So the approval gate is enforced by AWS itself.
> Second, **what you review is what gets deployed**. Each PR shows add, change, replace and destroy counts per
> environment with a warning on destructive changes, and on merge we apply the exact saved plan, encrypted
> between jobs.
> Third, **least privilege for people**. Admins and developers have no permissions on their IAM users; with
> MFA they assume a role. Developers get view-only access in AWS and Kubernetes, and can only open a tunnel
> through the bastion, not a shell."
>
> **Challenges.** "Real deployment surfaced issues validation never would. For example, the first GitHub
> deploy was denied by AWS. I traced it to GitHub's immutable OIDC subject format, which includes numeric
> owner and repo IDs, and I pinned those IDs in the trust policy, which also blocks repo-jacking."
>
> **Results.** "A change goes from PR to running infrastructure without anyone touching the console, there
> are zero AWS keys in GitHub, every action is attributable in CloudTrail and the EKS audit logs, and dev can
> be destroyed and recreated with one click, which kept costs to about 27 cents an hour."
>
> **Improvements.** "At company scale I'd use IAM Identity Center instead of IAM users, Karpenter, Argo CD
> for applications, and SCPs as account-level guardrails."

---

## 4. The 5-minute architecture walkthrough

Draw this:
```
 Developer ──PR──► GitHub Actions ──OIDC──► AWS account (one per env)
                    │                        ├─ S3 state (KMS, versioned, native lock)
   PR:   fmt/validate/tflint/checkov/plan    ├─ VPC: public / private / isolated DB subnets, 1 NAT (dev)
   merge: dev auto-apply                     ├─ EKS 1.35: private API, managed nodes, add-ons
          qa/prod approval                   └─ SSM bastion (no SSH, no public IP)
                                                  ▲
 People: IAM user ─MFA─► role ─SSM tunnel────────┘──► EKS access entry (admin / view)
```

| # | Topic | What to say (with the WHY) |
|---|---|---|
| 1 | Repo layout | Modules + one root per env; identical `main.tf`, different `tfvars` → promotion = same code moving forward. Chose this over workspaces because workspaces share backend and credentials. |
| 2 | State | S3 + KMS + versioning + **S3 native locking** (`use_lockfile`, Terraform ≥ 1.10, no DynamoDB). State holds secrets, so it's encrypted, recoverable and locked. |
| 3 | Bootstrap | One-time privileged layer: state bucket, OIDC, CI roles, people. Solves the chicken and egg. |
| 4 | Auth | GitHub OIDC → STS → 1-hour credentials. Plan role (PRs, read-only) vs apply role (environment-gated). |
| 5 | CI/CD | PR plan comment with a summary; merge applies the saved encrypted plan; drift detection nightly. |
| 6 | EKS | Private endpoint, access entries (no aws-auth), KMS secrets encryption, Pod Identity, IMDSv2 hop limit 1, managed add-ons in the correct order. |
| 7 | People | IAM users with zero permissions → MFA → role. Bastion is only a network hop; kubectl runs as each person. |
| 8 | Security scanning | tflint, Checkov (SARIF to the GitHub Security tab), actionlint, gitleaks pre-commit; every exception is an inline skip with a reason. |
| 9 | Cost | Feature flags (`enable_app_tier`), single NAT in dev, free-tier instance types, budget alert, destroy workflow. |

---

## 5. Deep dives by topic

### 5.1 Remote state
- Backend: S3, `encrypt = true`, `kms_key_id = alias/terraform-state`, `use_lockfile = true`.
- Bucket policy denies non-TLS and TLS < 1.2; public access blocked; versioning keeps 365 days of history for rollback.
- The plan role can **only write `*.tflock`**, never the state itself.
- The apply role is **explicitly denied** deleting or reconfiguring the state bucket and key.
- **Recovery:** restore the previous S3 object version. **Refactors:** `moved {}` blocks instead of manual `state mv`.

### 5.2 GitHub OIDC (how CI logs in to AWS)
```
job (id-token: write) → GitHub issues signed JWT {aud: sts.amazonaws.com, sub: repo:…:pull_request}
→ STS AssumeRoleWithWebIdentity → checks signature, iss, aud, sub vs trust policy → ASIA… creds ≤ 1h
```
- `sub` decides everything: `:pull_request`, `:ref:refs/heads/main` → **plan role**; `:environment:dev` → **apply role**.
- GitHub issues `environment:prod` tokens **only after** the environment's reviewers approve → the approval is enforced cryptographically.
- Immutable subject format: `repo:owner@ownerID/repo@repoID:…`. Pinning IDs blocks repo-jacking.
- Fork PRs never get an OIDC token. We never use `pull_request_target`.
- **OIDC vs PAT:** a PAT authenticates to **GitHub** as a user and can't log in to AWS. The pipeline uses the per-job `GITHUB_TOKEN` for PR comments.

### 5.3 CI/CD pipeline
- `terraform-ci` (every PR): fmt, validate (all roots), tflint, Checkov, plan for each configured env, then the PR comment.
- `terraform-deploy` (every merge to main): dev → qa → prod, each via the reusable `_terraform-apply.yml`:
  plan with the read-only role → encrypt the plan → artifact (1-day retention) → environment gate → decrypt → `apply tfplan`.
- Apply runs only when `plan -detailed-exitcode` returns **2** (changes).
- `concurrency` group per environment; never cancels a running apply.
- `terraform-destroy` (manual, type the env name to confirm), `terraform-drift` (nightly → issue), `bootstrap` (one-time).
- `_discover-envs.yml` skips environments without an account, so dev-only setups never fail on qa/prod.

### 5.4 Why encrypt the saved plan (`TF_PLAN_ENCRYPTION_KEY`)
Plan and apply run on different runners, so the plan travels as an artifact. Plan files contain resource
attributes in plain text, and artifacts on public repos are downloadable, so the plan is AES-256 encrypted
with a key in GitHub Secrets and kept for 1 day.

### 5.5 EKS 1.35
- `authentication_mode = "API"` (access entries), `bootstrap_cluster_creator_admin_permissions = false`.
- Secrets envelope encryption with a CMK; all 5 control-plane log types; `upgrade_policy = STANDARD` (avoids extended-support fees); deletion protection in qa/prod; zonal shift in prod.
- Add-ons: pod-identity-agent, vpc-cni (NetworkPolicy on, prefix delegation), kube-proxy **before nodes**; CoreDNS and EBS CSI **after nodes**.
- **Pod Identity** for vpc-cni and ebs-csi; the node role has only worker, ECR pull-only and SSM policies.
- Nodes: AL2023, IMDSv2 **hop limit 1** (pods can't reach node credentials), KMS-encrypted gp3, node auto-repair, 33% max unavailable during updates.
- No Kubernetes/Helm provider in Terraform: Terraform builds the platform, GitOps deploys the apps.

### 5.6 People, bastion and least privilege
- Users have **no permissions**; force-MFA policy; groups can assume exactly one role; trust policy requires the named user + MFA used within 1 hour.
- `developer-readonly`: `ViewOnlyAccess` (not `ReadOnlyAccess`, which can read S3 data) + `AmazonEKSViewPolicy` + SSM **port-forward document only** (`ssm:SessionDocumentAccessCheck`) through instances tagged `Role=bastion`.
- Bastion role is **view-only in EKS**, so there is no shared admin identity; people run kubectl locally through `scripts/eks-tunnel.sh`.
- Shell sessions: recorded to a KMS-encrypted log group, session data KMS-encrypted, 20 min idle / 60 min max.
- Passwords and keys are never created by Terraform (no secrets in state). The CI role is denied `iam:CreateUser`.

---

## 6. Issues we faced and how we fixed them

Tell each one as **Symptom → Root cause → How I found it → Fix → Lesson**. Pick 2–3 for any interview.

### Issue 1: OIDC login denied (the best story)
- **Symptom:** first GitHub deploy failed: `Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity`.
- **Root cause:** the trust policy allowed `sub = repo:vinaysinghhata5-oss/terraform-aws-platform:…`, but the repo
  uses GitHub's **immutable subject** format: `repo:vinaysinghhata5-oss@234816913/terraform-aws-platform@1406873367:…`.
  The strings didn't match, so AWS refused.
- **How I found it:** the error pointed at the trust policy; `gh api repos/<o>/<r>/actions/oidc/customization/sub`
  returned `use_immutable_subject: true` and the exact prefix.
- **Fix:** added `github_owner_id`/`github_repo_id` to bootstrap so the trust policy requires the IDs; re-ran bootstrap.
- **Lesson:** debug OIDC by comparing the token's `sub` with the trust policy character by character (CloudTrail
  `AssumeRoleWithWebIdentity` events). I kept the immutable format because names can be re-registered but IDs can't.

### Issue 2: wrong account ID in CI (variable precedence)
- **Symptom:** after login worked, plan failed with `AWS account ID not allowed`.
- **Root cause:** CI passed the real account ID as `TF_VAR_aws_account_id`, but **`TF_VAR_*` has the lowest
  precedence**, so the placeholder in `terraform.tfvars` won. The `allowed_account_ids` guard rejected it.
- **How I found it:** compared local (worked, because `local.auto.tfvars` outranks `terraform.tfvars`) with CI, then proved it with a tiny Terraform test.
- **Fix:** CI writes `ci.auto.tfvars.json`, which outranks `terraform.tfvars`.
- **Lesson:** know the precedence order (`-var` > `*.auto.tfvars` > `terraform.tfvars` > `TF_VAR_*` > defaults). The safety guard turned a dangerous mistake into a clean failure.

### Issue 3: launch template failed on empty tags
- **Symptom:** `InvalidTagSpecification.Malformed: The tags cannot be null or empty` creating the node launch template.
- **Root cause:** provider `default_tags` are **not** applied to launch template `tag_specifications`; the volume spec got an empty map.
- **Fix:** `data "aws_default_tags"` merged into tag specifications, which also gives nodes and volumes cost-allocation tags.
- **Lesson:** `default_tags` has gaps (tag specs, ASG-propagated tags). Verify tags on what is actually launched.

### Issue 4: bastion had no kubectl
- **Symptom:** verification step: `bash: kubectl: command not found`.
- **Root cause:** a **boot-order race**. The bastion started before the NAT route existed; user data couldn't download kubectl and stopped (`set -e`).
- **How I found it:** the download URLs worked from elsewhere (HTTP 200), and the instance had been created in the first apply, before the routes.
- **Fix:** wait for outbound network, `curl --retry`, log to `/var/log/bastion-setup.log`, `depends_on = [module.vpc]`; the verify step waits for `cloud-init status --wait`.
- **Lesson:** dependencies that Terraform can't see (network readiness) must be made explicit, and boot scripts must be idempotent and retrying.

### Issue 5: `for_each` on values unknown until apply (caught before deploying)
- **Symptom:** `validate` passed, but on review: `for_each` keyed by security group IDs and role ARNs created in the same apply → "Invalid for_each argument".
- **Fix:** static keys (`admin-0`, `readonly-0`) or `count = length(list)`.
- **Lesson:** `validate` and `plan` on an empty state don't prove a first apply works. Keys must be known at plan time.

### Issue 6: KMS key policy with a principal that doesn't exist yet (caught before deploying)
- **Root cause:** the key policy named the AutoScaling service-linked role, which doesn't exist in a fresh account until the first ASG, and KMS rejects unknown principals.
- **Fix:** `Principal = "*"` constrained by `aws:PrincipalArn` (a condition doesn't require the principal to exist).
- **Lesson:** design for a fresh account, not just yours.

### Issue 7: the bastion was a shared admin (design flaw found in review)
- **Problem:** anyone who could open a session on the bastion became EKS cluster-admin through the bastion's role, with no per-person audit.
- **Fix:** bastion role → view-only; people tunnel through it with **their own** MFA role (`eks-tunnel.sh`); developers can't open shells; sessions recorded.
- **Lesson:** a bastion should be a **network path, not an identity**.

### Issue 8: force-MFA policy blocked role assumption
- **Root cause:** requests signed with long-term access keys never carry `aws:MultiFactorAuthPresent`, so the standard "deny unless MFA" policy also blocked `sts:AssumeRole`, even with an MFA code.
- **Fix:** exempt `sts:AssumeRole` in the user policy; enforce MFA in the **role trust policy** instead (`aws:MultiFactorAuthPresent = true`, `MultiFactorAuthAge < 3600`).
- **Lesson:** know where each condition key exists; enforce MFA where it's actually evaluated.

### Issue 9: pipeline gaps found while using it
- **Path filters:** deploy only triggered on `envs/**` changes, so a merge changing scripts or workflows didn't deploy → now **every merge deploys**. CI had a path filter too, which would leave required checks pending forever → removed.
- **Unprotected environments:** GitHub **auto-creates** a referenced environment without protection, so prod could have applied without approval → created `qa`/`prod` with reviewers and wait timer up front.
- **Plan summary saved us:** after dev had been destroyed to save cost, a PR plan showed **➕ 79 to add**. Because the summary is the first line of the PR comment, it was obvious that merging would re-create the whole environment, not apply a small change. Solution: `DEPLOY_ENABLED=false` to pause deploys when merging while dev is off.

### Issue 10: Checkov findings triage
- Real fix: **Session Manager data wasn't KMS-encrypted** (CKV_AWS_112) → set `kmsKeyId` and granted narrowly scoped KMS permissions (developers by key alias).
- Accepted with a reason: IAM users instead of SSO (CKV_AWS_273). SSO needs AWS Organizations, which upgrades the Free-plan account.
- **Lesson:** treat scanners as reviewers: fix, or document an exception inline (`#checkov:skip=ID:reason`) so it is reviewed in the PR. Never blanket-disable.

### Issue 11: credentials exposed
- **What happened:** an access key was pasted into a chat during setup. It had to be treated as **compromised**: deleted and rotated.
- **Lesson:** exactly why the design uses OIDC for CI, MFA-gated roles for people, and nothing long-lived.

---

## 7. Question bank with model answers

**Terraform**
- *Workspaces vs directories?* Directories + separate accounts: separate state and credentials, so a smaller blast radius and clear diffs. Workspaces only for short-lived copies of the same environment.
- *State locking?* S3 native lock file (`use_lockfile`) since 1.10; the DynamoDB table is no longer needed. `force-unlock` only after confirming no run is active.
- *State corrupted or deleted?* Restore an S3 object version; `terraform import` / `import {}` blocks for orphans; `plan -refresh-only` to see drift.
- *How do you refactor without destroying?* `moved {}` blocks, reviewed in the PR.
- *How do you prevent destroying production data?* Plan summary with a destroy warning, approval gates, `deletion_protection`, final snapshots, S3 versioning, KMS deletion window, `prevent_destroy` on critical prod resources.
- *Variable precedence?* `-var`/`-var-file` > `*.auto.tfvars(.json)` > `terraform.tfvars` > `TF_VAR_*` > defaults (Issue 2).
- *Supply chain?* Committed lock file + `init -lockfile=readonly`, pinned versions, Dependabot, pin actions to SHAs.

**CI/CD and security**
- *How do pipelines authenticate to AWS?* OIDC (section 5.2). No secrets stored; credentials last 1 hour; scoped by `sub`.
- *How do you stop a PR from changing prod?* PR jobs get only the read-only role; the apply role trusts only `environment:prod`; reviewers + branch protection.
- *Why apply a saved plan?* What was reviewed is exactly what runs; stale plans are rejected.
- *How do you detect drift?* Nightly `plan -detailed-exitcode` (2 = drift) → GitHub issue.

**EKS**
- *How does kubectl authenticate?* `aws eks get-token` creates a pre-signed STS GetCallerIdentity token → EKS resolves the IAM ARN → access entry → access policy.
- *Access entries vs aws-auth?* An API with IAM-native management; no fragile ConfigMap; the creator isn't an implicit admin.
- *IRSA vs Pod Identity?* Both give pods scoped AWS credentials; Pod Identity needs no per-cluster OIDC provider and has a simpler trust policy.
- *Why IMDSv2 hop limit 1?* Containers are one network hop away, so they can't reach node credentials.
- *How do you upgrade 1.35 → 1.36?* Check deprecated APIs (upgrade insights), dev first: control plane → node groups (respect PDBs) → add-ons; one minor version at a time; promote through the pipeline.
- *How do you access a private cluster?* SSM port-forward through the bastion; kubectl runs as your own role.

**People and access**
- *How do you give developers read-only?* AWS `ViewOnlyAccess` + EKS `AmazonEKSViewPolicy` (namespace-scoped if needed) + tunnel-only SSM; MFA required (section 5.6).
- *SSO or IAM users?* SSO (IAM Identity Center) in any company; IAM users here only because of the Free-plan Organizations limitation.
- *Offboarding?* Remove from the list, re-run bootstrap → user, keys and MFA device deleted. With SSO: disable once in the identity provider.

---

## 8. Trade-offs and what I'd do at company scale

| Today (lab) | At company scale |
|---|---|
| IAM users + MFA → roles | IAM Identity Center (SSO) permission sets from Okta / Entra ID |
| Apply role = AdministratorAccess + deny guardrails | Scoped policy + permissions boundary + Organizations **SCPs** |
| Managed node group | **Karpenter** or EKS Auto Mode (bin-packing, Spot) |
| No app deployment tooling | **Argo CD / Flux** GitOps, AWS Load Balancer Controller, ExternalDNS, External Secrets |
| Checkov + tflint | + OPA/Conftest policy-as-code on the plan JSON, Infracost in PRs, `terraform test` / Terratest |
| One repo | Private module registry with versioned modules; Terragrunt or Atlantis/Spacelift for many teams |
| Bastion + SSM tunnel | Client VPN / Direct Connect for the corporate network; still no SSH |
| Single dev account | Control Tower / account vending; separate log-archive and security accounts with GuardDuty, Security Hub, org CloudTrail |

---

## 9. Commands to know cold

```bash
terraform plan -detailed-exitcode     # 0 none, 1 error, 2 changes
terraform plan -refresh-only          # drift without config changes
terraform apply tfplan                # apply a saved plan
terraform show -json tfplan | jq      # machine-readable plan (our summary uses this)
terraform state list | show | rm      # state inspection / surgery
terraform force-unlock <LOCK_ID>
terraform providers lock -platform=linux_amd64 -platform=darwin_arm64

aws sts get-caller-identity           # "who am I?" (first step of any auth debug)
aws eks update-kubeconfig --name acme-dev
kubectl auth can-i --list             # what can my identity do?
gh api repos/<o>/<r>/actions/oidc/customization/sub    # OIDC subject format
```
