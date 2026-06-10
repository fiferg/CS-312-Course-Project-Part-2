#!/usr/bin/env bash
# setup.sh — Full pipeline: provision infrastructure, then configure the server.
# Usage: ./setup.sh
# Requirements: terraform, ansible, aws CLI configured with valid credentials.

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[setup]${NC} $*"; }
warn() { echo -e "${YELLOW}[setup]${NC} $*"; }
die()  { echo -e "${RED}[setup] ERROR:${NC} $*" >&2; exit 1; }

# ── Preflight checks ──────────────────────────────────────────────────────────
log "Checking required tools..."
for tool in terraform ansible aws nmap; do
  command -v "$tool" &>/dev/null || die "'$tool' is not installed or not in PATH."
done

# Verify AWS credentials are set
aws sts get-caller-identity &>/dev/null || die "AWS credentials are not configured. Export AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_SESSION_TOKEN."

# ── Step 1: Terraform — provision infrastructure ──────────────────────────────
log "Step 1/4 — Initialising Terraform..."
cd "$(dirname "$0")/terraform"
terraform init -upgrade

log "Step 2/4 — Applying Terraform (this provisions EC2, VPC, security group, and key pair)..."
terraform apply -auto-approve

# Grab the public IP from Terraform output
INSTANCE_IP=$(terraform output -raw instance_public_ip)
log "Instance provisioned at: ${INSTANCE_IP}"

# ── Step 2: Write Ansible inventory ───────────────────────────────────────────
cd ../ansible
log "Step 3/4 — Generating Ansible inventory for ${INSTANCE_IP}..."
cat > inventory.ini <<EOF
[minecraft]
${INSTANCE_IP} ansible_user=ubuntu ansible_ssh_private_key_file=../MC-Key.pem ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

# ── Step 3: Wait for SSH to become available ──────────────────────────────────
log "Waiting for SSH to become available on ${INSTANCE_IP}..."
MAX_WAIT=120
ELAPSED=0
until ssh -i ../MC-Key.pem \
          -o StrictHostKeyChecking=no \
          -o ConnectTimeout=5 \
          ubuntu@"${INSTANCE_IP}" exit 2>/dev/null; do
  if [ "$ELAPSED" -ge "$MAX_WAIT" ]; then
    die "SSH did not become available within ${MAX_WAIT}s."
  fi
  warn "  SSH not ready yet — retrying in 10s..."
  sleep 10
  ELAPSED=$((ELAPSED + 10))
done
log "SSH is ready."

# ── Step 4: Ansible — configure the server ───────────────────────────────────
log "Step 4/4 — Running Ansible playbook to install Java, download server JAR, and configure systemd..."
ansible-playbook -i inventory.ini playbook.yml

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
log "✅ Done! Your Minecraft server is running."
log "   Public IP : ${INSTANCE_IP}"
log "   Verify    : nmap -sV -Pn -p T:25565 ${INSTANCE_IP}"
log "   Connect   : add '${INSTANCE_IP}' as a server in Minecraft 1.21.4"
