#!/usr/bin/env bash
# Run kubectl from your laptop against the PRIVATE EKS API, as YOUR OWN identity.
# The bastion is only a network hop (SSM port-forward); kubectl signs requests with
# your profile's role, so EKS applies your permissions and the audit log shows you.
#
# Usage:  AWS_PROFILE=amar-dev ./scripts/eks-tunnel.sh [cluster] [local-port]
# Needs:  aws CLI v2, session-manager-plugin, kubectl
#         (brew install awscli kubectl && brew install --cask session-manager-plugin)
set -euo pipefail

CLUSTER="${1:-acme-dev}"
LOCAL_PORT="${2:-8443}"
REGION="${AWS_REGION:-us-east-1}"
PROFILE="${AWS_PROFILE:?set AWS_PROFILE to your role profile, e.g. vinay-admin or amar-dev}"
CONTEXT="${CLUSTER}-tunnel"

for bin in aws kubectl session-manager-plugin; do
  command -v "$bin" >/dev/null || { echo "missing: $bin"; exit 1; }
done

echo "Identity: $(aws sts get-caller-identity --query Arn --output text)"

BASTION_ID="$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Role,Values=bastion" "Name=tag:Name,Values=${CLUSTER}-bastion" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)"
[ "$BASTION_ID" != "None" ] || { echo "No running bastion for $CLUSTER"; exit 1; }

read -r CLUSTER_ARN ENDPOINT < <(aws eks describe-cluster --region "$REGION" --name "$CLUSTER" \
  --query '[cluster.arn, cluster.endpoint]' --output text)
API_HOST="${ENDPOINT#https://}"

# kubeconfig: talk to localhost, but verify the TLS cert against the real API hostname.
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER" --alias "$CONTEXT" --profile "$PROFILE" >/dev/null
kubectl config set-cluster "$CLUSTER_ARN" --server="https://localhost:${LOCAL_PORT}" --tls-server-name="$API_HOST" >/dev/null
kubectl config use-context "$CONTEXT" >/dev/null

cat <<MSG
Tunnel: localhost:${LOCAL_PORT} -> bastion ${BASTION_ID} -> ${API_HOST}:443
kubectl context '${CONTEXT}' is ready. In ANOTHER terminal run e.g.:
  kubectl get nodes
  kubectl auth can-i --list
Press Ctrl+C here to close the tunnel.
MSG

exec aws ssm start-session --region "$REGION" --target "$BASTION_ID" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "host=${API_HOST},portNumber=443,localPortNumber=${LOCAL_PORT}"
