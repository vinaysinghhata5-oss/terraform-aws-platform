#!/bin/bash
# Placeholder workload: serves /health on 8080 so the ALB health check passes.
set -euo pipefail
dnf install -y python3
mkdir -p /opt/app && cd /opt/app
echo "ok" > health
nohup python3 -m http.server 8080 --directory /opt/app >/var/log/app.log 2>&1 &
