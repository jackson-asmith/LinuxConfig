#!/bin/bash
set -euo pipefail
trap 'echo "ERROR: script failed at line $LINENO" >&2' ERR

# Base system setup for RHEL-based hosts.
# Configures: hostname, packages, NTP, SELinux, admin user, SSH hardening,
#             firewall, sysctl hardening, auditd, PAM lockout, automatic
#             updates, core dump disabling, and login banner.
#
# Required variables:
#   HOSTNAME      Short hostname for the server
#   FQDN          Fully qualified domain name
#   ADMIN_USER    Non-root sudoer account to create
#
# Optional variables:
#   ADMIN_SSH_KEY            Public key for the admin user's authorized_keys
#   NTP_SERVERS              Space-separated NTP server list
#                            (default: AD_SERVER if set, then pool.ntp.org)
#   SSH_PORT                 SSH port (default: 22)
#   FIREWALL_EXTRA_SERVICES  Space-separated extra firewalld services to allow
#   LOGIN_BANNER             Banner text written to /etc/issue and /etc/issue.net
#   DRY_RUN                  Set to "true" to print commands without executing

: "${HOSTNAME:?HOSTNAME must be set}"
: "${FQDN:?FQDN must be set}"
: "${ADMIN_USER:?ADMIN_USER must be set}"

SSH_PORT="${SSH_PORT:-22}"
DRY_RUN="${DRY_RUN:-false}"

# Wraps side-effectful commands: executes normally or prints in dry-run mode.
# Read-only operations (grep, id, getenforce, etc.) are called directly.
run() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] $*"
    else
        "$@"
    fi
}

[[ "$DRY_RUN" == "true" ]] && echo "--- Dry-run mode enabled: no changes will be made ---"

# Detect primary IPv4 address (works with predictable interface names)
IPADDR=$(ip -4 addr show scope global | awk '/inet / { print $2 }' | cut -d/ -f1 | head -1)

# ── Packages ──────────────────────────────────────────────────────────────────

run dnf update -y
run dnf install -y \
    chrony \
    firewalld \
    dnf-automatic \
    audit \
    libpwquality

# ── Hostname ──────────────────────────────────────────────────────────────────

run hostnamectl set-hostname "$FQDN"

if ! grep -qF "$FQDN" /etc/hosts; then
    run bash -c "echo '$IPADDR $FQDN $HOSTNAME' >> /etc/hosts"
fi

# ── SELinux ───────────────────────────────────────────────────────────────────

# Ensure SELinux is enforcing. If it was disabled, a reboot is required;
# the script will exit with a clear message rather than silently continuing.
SELINUX_STATUS=$(getenforce 2>/dev/null || echo "Unknown")
if [[ "$SELINUX_STATUS" == "Disabled" ]]; then
    echo "ERROR: SELinux is disabled. Set SELINUX=enforcing in /etc/selinux/config and reboot." >&2
    exit 1
elif [[ "$SELINUX_STATUS" == "Permissive" ]]; then
    echo "WARNING: SELinux is permissive, setting to enforcing..."
    run setenforce 1
    run sed -i 's/^SELINUX=permissive/SELINUX=enforcing/' /etc/selinux/config
fi

# ── NTP ───────────────────────────────────────────────────────────────────────

# Kerberos requires clocks to be within 5 minutes of the AD server.
# Default to AD_SERVER (available when run via deploy.sh) + public fallback.
NTP_SERVERS="${NTP_SERVERS:-${AD_SERVER:-} pool.ntp.org}"

run bash -c "cat > /etc/chrony.conf <<EOF
# Managed by base-setup.sh
$(for server in $NTP_SERVERS; do [[ -n "$server" ]] && echo "server $server iburst"; done)
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
EOF"

run systemctl enable --now chronyd
run chronyc makestep

# ── Kernel / sysctl hardening ─────────────────────────────────────────────────

# Covers CIS Benchmark Level 1 network and kernel parameter recommendations.
run bash -c "cat > /etc/sysctl.d/90-hardening.conf <<'EOF'
# Managed by base-setup.sh

# Prevent SYN flood attacks
net.ipv4.tcp_syncookies = 1

# Disable IP source routing and ICMP redirects
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.secure_redirects = 0

# Enable reverse path filtering to prevent IP spoofing
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore broadcast ICMP requests
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Disable IPv6 if not in use
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1

# Address space layout randomisation
kernel.randomize_va_space = 2

# Prevent core dumps from exposing sensitive memory
fs.suid_dumpable = 0
EOF"

run sysctl --system

# ── Core dumps ────────────────────────────────────────────────────────────────

run bash -c "cat > /etc/security/limits.d/90-coredump.conf <<'EOF'
# Managed by base-setup.sh
*    hard    core    0
EOF"

run mkdir -p /etc/systemd/coredump.conf.d
run bash -c "cat > /etc/systemd/coredump.conf.d/90-disable.conf <<'EOF'
[Coredump]
Storage=none
ProcessSizeMax=0
EOF"

# ── Audit daemon ──────────────────────────────────────────────────────────────

run systemctl enable --now auditd

# ── PAM lockout (faillock) ────────────────────────────────────────────────────

run bash -c "cat > /etc/security/faillock.conf <<'EOF'
# Managed by base-setup.sh
deny = 5
unlock_time = 900
silent
audit
EOF"

# ── Admin user ────────────────────────────────────────────────────────────────

if ! id "$ADMIN_USER" &>/dev/null; then
    run useradd -m -s /bin/bash "$ADMIN_USER"
fi
run usermod -aG wheel "$ADMIN_USER"

SSH_DIR="/home/${ADMIN_USER}/.ssh"
run mkdir -p "$SSH_DIR"
run chmod 700 "$SSH_DIR"

if [[ -n "${ADMIN_SSH_KEY:-}" ]]; then
    run bash -c "echo '${ADMIN_SSH_KEY}' > '${SSH_DIR}/authorized_keys'"
    run chmod 600 "${SSH_DIR}/authorized_keys"
fi

run chown -R "${ADMIN_USER}:${ADMIN_USER}" "$SSH_DIR"

# ── SSH hardening ─────────────────────────────────────────────────────────────

run mkdir -p /etc/ssh/sshd_config.d

run bash -c "cat > /etc/ssh/sshd_config.d/90-hardening.conf <<EOF
# Managed by base-setup.sh
AddressFamily inet
Port ${SSH_PORT}
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
X11Forwarding no
MaxAuthTries 4
Banner /etc/issue.net
EOF"

if [[ "$SSH_PORT" != "22" ]]; then
    run semanage port -a -t ssh_port_t -p tcp "$SSH_PORT" 2>/dev/null \
        || run semanage port -m -t ssh_port_t -p tcp "$SSH_PORT"
fi

run systemctl restart sshd

# ── Firewall ──────────────────────────────────────────────────────────────────

run systemctl enable --now firewalld

if [[ "$SSH_PORT" == "22" ]]; then
    run firewall-cmd --permanent --add-service=ssh
else
    run firewall-cmd --permanent --remove-service=ssh 2>/dev/null || true
    run firewall-cmd --permanent --add-port="${SSH_PORT}/tcp"
fi

run firewall-cmd --permanent --add-service=kerberos

for svc in ${FIREWALL_EXTRA_SERVICES:-}; do
    run firewall-cmd --permanent --add-service="$svc"
done

run firewall-cmd --reload
firewall-cmd --list-all 2>/dev/null || true

# ── Automatic security updates ────────────────────────────────────────────────

run sed -i 's/^upgrade_type\s*=.*/upgrade_type = security/' /etc/dnf/automatic.conf
run sed -i 's/^apply_updates\s*=.*/apply_updates = yes/' /etc/dnf/automatic.conf
run sed -i 's/^emit_via\s*=.*/emit_via = motd/' /etc/dnf/automatic.conf
run systemctl enable --now dnf-automatic.timer

# ── Login banner ──────────────────────────────────────────────────────────────

LOGIN_BANNER="${LOGIN_BANNER:-"Authorized use only. All activity may be monitored and reported."}"
run bash -c "echo '${LOGIN_BANNER}' | tee /etc/issue /etc/issue.net > /dev/null"

echo "Base setup complete for ${HOSTNAME} (${FQDN})"
