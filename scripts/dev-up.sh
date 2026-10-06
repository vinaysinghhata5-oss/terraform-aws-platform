#!/usr/bin/env bash
# Provision the dev environment end to end:
#   bootstrap (state bucket, KMS, OIDC roles, budget) -> plan -> confirm -> apply -> verify kubectl on bastion
# Usage:  AWS_PROFILE=dev ./scripts/dev-up.sh            (or export AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGION="${AWS_REGION:-us-east-1}"
BUDGET_EMAIL="${BUDGET_EMAIL:-}"
SCRATCH="/private/tmp/claude-501/-Users-vinaysingh-Downloads/fb075c5e-d081-4099-bce0-b6114b58944b/scratchpad"
TF="$(command -v terraform || echo "$SCRATCH/terraform")"
AWS="$(command -v aws || echo "$SCRATCH/venv/bin/aws")"
export AWS_REGION="$REGION" AWS_DEFAULT_REGION="$REGION"

[ -x "$TF" ]  || { echo "terraform not found - brew install terraform"; exit 1; }
[ -x "$AWS" ] || { echo "aws cli not found - brew install awscli"; exit 1; }

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

step "Checking AWS identity"
ACCOUNT_ID="$("$AWS" sts get-caller-identity --query Account --output text)"
CALLER_ARN="$("$AWS" sts get-caller-identity --query Arn --output text)"
echo "Account: $ACCOUNT_ID   Caller: $CALLER_ARN"

step "Bootstrap: state bucket, KMS key, GitHub OIDC roles, budget alert"
TF="$TF" AWS="$AWS" BUDGET_EMAIL="$BUDGET_EMAIL" "$ROOT/scripts/bootstrap.sh" dev
STATE_BUCKET="acme-tfstate-${ACCOUNT_ID}-${REGION}"

step "Writing git-ignored envs/dev/local.auto.tfvars"
cat > "$ROOT/envs/dev/local.auto.tfvars" <<VARS
aws_account_id           = "$ACCOUNT_ID"
region                   = "$REGION"
eks_admin_principal_arns = ["$CALLER_ARN"]
VARS

step "terraform init (remote state: s3://$STATE_BUCKET)"
"$TF" -chdir="$ROOT/envs/dev" init -input=false -reconfigure \
  -backend-config="bucket=$STATE_BUCKET" -backend-config="region=$REGION"

step "terraform plan"
"$TF" -chdir="$ROOT/envs/dev" plan -input=false -out=tfplan
echo
"$TF" -chdir="$ROOT/envs/dev" show -no-color tfplan | grep -E '^Plan:' || true
echo "Estimated cost while running: ~\$0.27/hour (EKS + NAT + 2 small EC2). Destroy with ./scripts/dev-down.sh"
read -r -p "Apply this plan? Type 'yes' to continue: " ok
[ "$ok" = "yes" ] || { echo "Aborted - nothing created except bootstrap."; exit 0; }

step "terraform apply (EKS takes ~15-20 minutes)"
"$TF" -chdir="$ROOT/envs/dev" apply -input=false tfplan
rm -f "$ROOT/envs/dev/tfplan"

step "Verifying: kubectl get nodes on the bastion (via SSM)"
BASTION_ID="$("$TF" -chdir="$ROOT/envs/dev" output -raw bastion_instance_id)"
for i in $(seq 1 30); do
  if [ "$("$AWS" ssm describe-instance-information --filters "Key=InstanceIds,Values=$BASTION_ID" --query 'length(InstanceInformationList)' --output text)" = "1" ]; then break; fi
  echo "waiting for bastion to register with SSM ($i/30)..."; sleep 10
done
CMD_ID="$("$AWS" ssm send-command --instance-ids "$BASTION_ID" --document-name AWS-RunShellScript \
  --parameters 'commands=["sudo -iu ec2-user bash -lc \"kubectl get nodes -o wide && kubectl get pods -A\""]' \
  --query Command.CommandId --output text)"
sleep 15
"$AWS" ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$BASTION_ID" \
  --query '[Status,StandardOutputContent,StandardErrorContent]' --output text || true

step "Done"
"$TF" -chdir="$ROOT/envs/dev" output
cat <<MSG

Connect to the bastion:
  - Browser: EC2 console -> Instances -> $BASTION_ID -> Connect -> Session Manager
    then run:  sudo su - ec2-user   and   kubectl get nodes
  - CLI:     aws ssm start-session --target $BASTION_ID   (needs the session-manager-plugin)

When finished practising:  ./scripts/dev-down.sh
MSG
