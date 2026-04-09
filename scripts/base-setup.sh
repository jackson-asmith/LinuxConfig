#!/bin/bash
set -euo pipefail
trap 'echo "ERROR: script failed at line $LINENO" >&2' ERR

# Base system setup: hostname, packages, SSH hardening, admin user.
#
# Required variables:
#   HOSTNAME      Short hostname for the server
#   FQDN          Fully qualified domain name
#   ADMIN_USER    Non-root sudoer account to create
#
# Optional variables:
#   ADMIN_SSH_KEY  Public key to install in the admin user's authorized_keys

: "${HOSTNAME:?HOSTNAME must be set}"
: "${FQDN:?FQDN must be set}"
: "${ADMIN_USER:?ADMIN_USER must be set}"

# Detect primary IPv4 address (works with predictable interface names)
IPADDR=$(ip -4 addr show scope global | awk '/inet / { print $2 }' | cut -d/ -f1 | head -1)

# Update packages
apt-get update
apt-get upgrade -y

# Set hostname
echo "$HOSTNAME" > /etc/hostname
hostname -F /etc/hostname

# Add FQDN to /etc/hosts (idempotent)
if ! grep -qF "$FQDN" /etc/hosts; then
    echo "$IPADDR $FQDN $HOSTNAME" >> /etc/hosts
fi

# Configure unattended-upgrades
apt-get install -y unattended-upgrades

# Create admin user (idempotent)
if ! id "$ADMIN_USER" &>/dev/null; then
    adduser --disabled-password --gecos "" "$ADMIN_USER"
fi
adduser "$ADMIN_USER" sudo

# SSH hardening (idempotent)
if ! grep -q 'AddressFamily inet' /etc/ssh/sshd_config; then
    echo 'AddressFamily inet' >> /etc/ssh/sshd_config
fi

if ! grep -q 'PermitRootLogin no' /etc/ssh/sshd_config; then
    echo 'PermitRootLogin no' >> /etc/ssh/sshd_config
fi

systemctl restart sshd

# Set up .ssh directory for admin user
SSH_DIR="/home/${ADMIN_USER}/.ssh"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [[ -n "${ADMIN_SSH_KEY:-}" ]]; then
    echo "$ADMIN_SSH_KEY" > "${SSH_DIR}/authorized_keys"
    chmod 600 "${SSH_DIR}/authorized_keys"
fi

chown -R "${ADMIN_USER}:${ADMIN_USER}" "$SSH_DIR"

echo "Base setup complete for ${HOSTNAME} (${FQDN})"
