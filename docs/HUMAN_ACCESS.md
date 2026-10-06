# Human access (admins & developers)

```
IAM user (no permissions) ──MFA──► role ──► AWS + EKS permissions
  vinay    (platform-admins) ──► platform-admin     : AWS admin, EKS cluster-admin, bastion shell
  amar-dev (developers)      ──► developer-readonly : AWS ViewOnly (no data), EKS view, bastion TUNNEL only
```

| Control | How |
|---|---|
| No standing permissions | Users only manage their own password/MFA/keys and may assume ONE role |
| MFA everywhere | Without MFA everything is denied; role trust needs MFA used within the last hour |
| Least privilege | Developers: `ViewOnlyAccess` (not `ReadOnlyAccess`, which can read S3 data) + EKS `AmazonEKSViewPolicy` (no exec, no Secrets, no writes) |
| Private cluster | EKS API is private; reach it via SSM port-forward through the bastion |
| No shared admin identity | Bastion role is view-only; kubectl runs on your laptop as YOUR role → per-person EKS audit logs |
| Developers can't use the bastion shell | `ssm:SessionDocumentAccessCheck` + only the port-forward document allowed |
| Recorded, time-boxed sessions | Bastion shells streamed to a KMS-encrypted log group; 20 min idle / 60 min max; session data KMS-encrypted |
| No secrets in Terraform state | Passwords and access keys are created by each person, never by Terraform |
| Pipeline can't create people | CI apply role is denied `iam:CreateUser`/`CreateAccessKey`; people live in `bootstrap/` |

> In a company, replace IAM users with **IAM Identity Center (SSO)** permission sets. It needs AWS
> Organizations, which would upgrade this Free-plan account, so this lab uses MFA-gated role assumption.

## Onboarding a person (admin does steps 1-2, the person does 3-6)

1. Add the name to `admin_users` or `developer_users` in `bootstrap/<env>.tfvars`, run `./scripts/bootstrap.sh <env>`.
2. Console → IAM → Users → *name* → **Security credentials → Enable console access**, auto-generated
   password, **"must create a new password at next sign-in"**. Send the sign-in URL + password separately.
3. Person signs in, sets a new password, then **Assign MFA device** (authenticator app). Sign out and back in with MFA.
4. Person creates **their own access key** (Security credentials → Create access key → CLI).
5. Person configures the CLI (`~/.aws/config`):
   ```ini
   [profile amar]
   region = us-east-1

   [profile amar-dev]                      # use this one
   source_profile = amar
   role_arn       = arn:aws:iam::<ACCOUNT_ID>:role/developer-readonly   # admins: role/platform-admin
   mfa_serial     = arn:aws:iam::<ACCOUNT_ID>:mfa/amar-dev               # from the MFA device page
   duration_seconds = 3600
   ```
   `aws configure --profile amar` stores the key; every command with `--profile amar-dev` asks for the MFA code.
6. Use the cluster:
   ```bash
   AWS_PROFILE=amar-dev ./scripts/eks-tunnel.sh          # keeps a tunnel open
   kubectl get pods -A                                   # (another terminal) ✅
   kubectl auth can-i delete pods                        # no ✅
   kubectl get secrets -A                                # Forbidden ✅
   ```

Console access to the role: **Switch role** → account ID + `developer-readonly` (or `platform-admin`).

## Offboarding
Remove the name from the tfvars list and re-run bootstrap: the user, keys and MFA device are deleted.
