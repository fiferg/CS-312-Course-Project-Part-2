#!/usr/bin/env bash
# destroy.sh — Tear down all AWS resources created by setup.sh.
# Usage: ./destroy.sh

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[destroy]${NC} $*"; }
die() { echo -e "${RED}[destroy] ERROR:${NC} $*" >&2; exit 1; }

aws sts get-caller-identity &>/dev/null || die "AWS credentials not configured."

log "Destroying all Terraform-managed AWS resources..."
cd "$(dirname "$0")/terraform"
terraform destroy -auto-approve

log "✅ All resources destroyed."
