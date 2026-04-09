#!/bin/bash
set -euo pipefail
trap 'echo "ERROR: script failed at line $LINENO" >&2' ERR

# Base system setup for RHEL-based hosts.
# Configures: hostname, packages, NTP, SSH hardening, admin user,
#             firewall, and SELinux.
#
# Required variables:
#   HOSTNAME      Short hostname for the server
#   FQDN          Fully qualified domain name
#   ADMIN_USER    Non-root sudoer account to create
#
# Optional variables:
#   ADMIN_SSH_KEY     Public key to install in the admin user's authorized_keys
#   NTP_SERVERS       Space-separated NTP server list (default: AD server + pool.ntp.org)
#   SSH_PORT          SSH port (default: 22)
#   FIREWALL_EXTRA_SERVICES  Space-separated firewalld services to allow beyond defaults

: "${HOSTNAME:?HOSTNAME must be set}"
: "${FQDN:?FQDN must be set}"
: "${ADMIN_USER:?ADMIN_USER must be set}"

SSH_PORT="${SSH_PORT:-22}"

# Detect primary IPv4 address (works with predictable interface names)
IPADDR=$(ip -4 addr show scope global | awk '/inet / { print $2 }' | cut -d/ -f1 | head -1)

# ── Packages ──────────────────────────────────────────────────────────────────

dnf update -y
dnf install -y chrony firewalld

# ── Hostname ──────────────────────────────────────────────────────────────────

hostnamectl set-hostname "$FQDN"

if ! grep -qF "$FQDN" /etc/hosts; then
    echo "$IPADDR $FQDN $HOSTNAME" >> /etc/hosts
fi

# ── SELinux ───────────────────────────────────────────────────────────────────

# Ensure SELinux is enforcing. If it was disabled, a reboot is required;
# the script will exit with a clear message rather than silently continuing.
SELINUX_STATUS=$(getenforce)
if [[ "$SELINUX_STATUS" == "Disabled" ]]; then
    echo "ERROR: SELinux is disabled. Set SELINUX=enforcing in /etc/selinux/config and reboot." >&2
    exit 1
elif [[ "$SELINUX_STATUS" == "Permissive" ]]; then
    echo "WARNING: SELinux is permissive, setting to enforcing..."
    setenforce 1
    sed -i 's/^SELINUX=permissive/SELINUX=enforcing/' /etc/selinux/config
fi

# ── NTP ───────────────────────────────────────────────────────────────────────

# Kerberos requires clocks to be within 5 minutes of the AD server.
# Default to AD_SERVER (set by ad-join.sh context) + public fallback.
NTP_SERVERS="${NTP_SERVERS:-${AD_SERVER:-} pool.ntp.org}"

{
    echo "# Managed by base-setup.sh"
    for server in $NTP_SERVERS; do
        [[ -n "$server" ]] && echo "server $server iburst"
    done
    echo "driftfile /var/lib/chrony/drift"
    echo "makestep 1.0 3"
    echo "rtcsync"
} > /etc/chrony.conf

systemctl enable --now chronyd
chronyc makestep

# ── Admin user ────────────────────────────────────────────────────────────────

if ! id "$ADMIN_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$ADMIN_USER"
fi
usermod -aG wheel "$ADMIN_USER"

SSH_DIR="/home/${ADMIN_USER}/.ssh"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [[ -n "${ADMIN_SSH_KEY:-}" ]]; then
    echo "$ADMIN_SSH_KEY" > "${SSH_DIR}/authorized_keys"
    chmod 600 "${SSH_DIR}/authorized_keys"
fi

chown -R "${ADMIN_USER}:${ADMIN_USER}" "$SSH_DIR"

# ── SSH hardening ─────────────────────────────────────────────────────────────

# Use a drop-in rather than modifying sshd_config directly.
mkdir -p /etc/ssh/sshd_config.d

cat > /etc/ssh/sshd_config.d/90-hardening.conf <<EOF
# Managed by base-setup.sh
AddressFamily inet
Port ${SSH_PORT}
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
X11Forwarding no
MaxAuthTries 4
EOF

# If a non-standard port is set, ensure SELinux allows it
if [[ "$SSH_PORT" != "22" ]]; then
    semanage port -a -t ssh_port_t -p tcp "$SSH_PORT" 2>/dev/null \
        || semanage port -m -t ssh_port_t -p tcp "$SSH_PORT"
fi

systemctl restart sshd

# ── Firewall ──────────────────────────────────────────────────────────────────

systemctl enable --now firewalld

# Remove SSH service if using a non-standard port (add port directly instead)
if [[ "$SSH_PORT" == "22" ]]; then
    firewall-cmd --permanent --add-service=ssh
else
    firewall-cmd --permanent --remove-service=ssh 2>/dev/null || true
    firewall-cmd --permanent --add-port="${SSH_PORT}/tcp"
fi

# Kerberos (required for AD authentication)
firewall-cmd --permanent --add-service=kerberos

# Allow any caller-specified additional services
for svc in ${FIREWALL_EXTRA_SERVICES:-}; do
    firewall-cmd --permanent --add-service="$svc"
done

firewall-cmd --reload
firewall-cmd --list-all

echo "Base setup complete for ${HOSTNAME} (${FQDN})"
