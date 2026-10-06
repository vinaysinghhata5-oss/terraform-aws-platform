#!/usr/bin/env bash
# Destroy the dev environment (keeps the cheap bootstrap state bucket / OIDC roles).
# Usage:  AWS_PROFILE=dev ./scripts/dev-down.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="/private/tmp/claude-501/-Users-vinaysingh-Downloads/fb075c5e-d081-4099-bce0-b6114b58944b/scratchpad"
TF="$(command -v terraform || echo "$SCRATCH/terraform")"
export AWS_REGION="${AWS_REGION:-us-east-1}" AWS_DEFAULT_REGION="${AWS_REGION:-us-east-1}"

"$TF" -chdir="$ROOT/envs/dev" destroy -input=false
echo "Dev destroyed. Bootstrap (state bucket, OIDC roles, budget) is kept - it costs ~\$1/month for the KMS key."
