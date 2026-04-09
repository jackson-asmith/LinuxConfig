#!/bin/bash
set -euo pipefail
trap 'echo "ERROR: script failed at line $LINENO" >&2' ERR

# Installs a daily cron job that rejoins the host to Active Directory if the
# domain membership is lost. Also adds a service account to the wheel group.
#
# Required variables:
#   AD_DOMAIN      AD domain name             (e.g. example.com)
#   AD_JOIN_USER   AD account used to rejoin  (e.g. linux_join)
#   AD_JOIN_PASS   Password for AD_JOIN_USER
#
# Optional variables:
#   WHEEL_USER     Local user to add to wheel group
#   REJOIN_SCRIPT  Path to install the rejoin script (default: /usr/local/sbin/ad-rejoin.sh)
#   DRY_RUN        Set to "true" to print commands without executing

: "${AD_DOMAIN:?AD_DOMAIN must be set}"
: "${AD_JOIN_USER:?AD_JOIN_USER must be set}"
: "${AD_JOIN_PASS:?AD_JOIN_PASS must be set}"

REJOIN_SCRIPT="${REJOIN_SCRIPT:-/usr/local/sbin/ad-rejoin.sh}"
DRY_RUN="${DRY_RUN:-false}"

run() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] $*"
    else
        "$@"
    fi
}

[[ "$DRY_RUN" == "true" ]] && echo "--- Dry-run mode enabled: no changes will be made ---"

# Install required packages
run yum install -y oddjob oddjob-mkhomedir sssd adcli realmd

# Write the rejoin script (credentials come from environment at install time;
# the script stores them locally with root-only permissions)
run bash -c "cat > '${REJOIN_SCRIPT}' <<'EOF'
#!/bin/bash
set -euo pipefail

AD_JOIN_USER=\"${AD_JOIN_USER}\"
AD_JOIN_PASS=\"${AD_JOIN_PASS}\"
AD_DOMAIN=\"${AD_DOMAIN}\"

if realm list | grep -q \"domain-name: \${AD_DOMAIN}\"; then
    exit 0
fi

echo \"Domain membership lost, rejoining \${AD_DOMAIN}...\"
realm leave 2>/dev/null || true
sleep 1
echo \"\$AD_JOIN_PASS\" | realm join --user=\"\$AD_JOIN_USER\" \"\$AD_DOMAIN\"
sleep 1

sed -i 's/use_fully_qualified_names = True/use_fully_qualified_names = False/' /etc/sssd/sssd.conf
sed -i 's|fallback_homedir = /home/%u@%d|fallback_homedir = /home/%u|' /etc/sssd/sssd.conf

systemctl stop sssd
systemctl start sssd
systemctl daemon-reload
EOF"

run chown root:root "$REJOIN_SCRIPT"
run chmod 700 "$REJOIN_SCRIPT"

# Install cron job — idempotency check runs regardless of dry-run mode.
CRON_JOB="0 0 * * * ${REJOIN_SCRIPT}"
if crontab -l 2>/dev/null | grep -qF "$REJOIN_SCRIPT"; then
    echo "Cron job already installed, skipping."
elif [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] crontab: ${CRON_JOB}"
else
    ( crontab -l 2>/dev/null; echo "$CRON_JOB" ) | crontab -
    echo "Cron job installed: ${CRON_JOB}"
fi

# Add optional wheel user
if [[ -n "${WHEEL_USER:-}" ]]; then
    run usermod -aG wheel "$WHEEL_USER"
    echo "Added ${WHEEL_USER} to wheel group."
fi

# Run once immediately to verify domain membership
if [[ "$DRY_RUN" != "true" ]]; then
    "$REJOIN_SCRIPT"
fi

echo "AD rejoin cron setup complete."
