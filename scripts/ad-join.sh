#!/bin/bash
set -euo pipefail
trap 'echo "ERROR: script failed at line $LINENO" >&2' ERR

# Joins the host to Active Directory and configures Kerberos, SSSD, and sudo.
#
# Required variables:
#   AD_DOMAIN      AD domain name              (e.g. example.com)
#   AD_SERVER      AD domain controller FQDN   (e.g. dc-01.example.com)
#   KRB5_REALM     Kerberos realm (uppercase)  (e.g. EXAMPLE.COM)
#   AD_JOIN_USER   AD account used to join     (e.g. linux_join)
#   AD_JOIN_PASS   Password for AD_JOIN_USER
#
# Optional variables:
#   DRY_RUN        Set to "true" to print commands without executing

: "${AD_DOMAIN:?AD_DOMAIN must be set}"
: "${AD_SERVER:?AD_SERVER must be set}"
: "${KRB5_REALM:?KRB5_REALM must be set}"
: "${AD_JOIN_USER:?AD_JOIN_USER must be set}"
: "${AD_JOIN_PASS:?AD_JOIN_PASS must be set}"

DRY_RUN="${DRY_RUN:-false}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] $*"
    else
        "$@"
    fi
}

[[ "$DRY_RUN" == "true" ]] && echo "--- Dry-run mode enabled: no changes will be made ---"

# Update packages
run yum update -y

# Crypto policy required for AD Kerberos compatibility
run update-crypto-policies --set DEFAULT:AD-SUPPORT

# Verify LDAP SRV records exist before attempting join
if [[ "$DRY_RUN" != "true" ]]; then
    dig -t SRV "_ldap._tcp.${AD_DOMAIN}" +short | grep -q '.' \
        || { echo "ERROR: No LDAP SRV records found for ${AD_DOMAIN}" >&2; exit 1; }
else
    echo "[DRY RUN] dig -t SRV _ldap._tcp.${AD_DOMAIN} +short"
fi

# Install required packages
run yum install -y realmd adcli sssd sssd-tools oddjob oddjob-mkhomedir \
    krb5-workstation krb5-libs authselect

# Apply Kerberos config from template
run bash -c "envsubst < '${SCRIPT_DIR}/../config/krb5.conf.tmpl' > /etc/krb5.conf"

# Join domain (idempotent)
if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] realm join --user=${AD_JOIN_USER} ${AD_SERVER}"
elif ! realm list | grep -q "domain-name: ${AD_DOMAIN}"; then
    echo "Joining domain ${AD_DOMAIN}..."
    echo "$AD_JOIN_PASS" | realm join --user="$AD_JOIN_USER" "$AD_SERVER"
else
    echo "Already joined to ${AD_DOMAIN}, skipping join."
fi

# Apply SSSD config from template
run bash -c "envsubst < '${SCRIPT_DIR}/../config/sssd.conf.tmpl' > /etc/sssd/sssd.conf"
run chown root:root /etc/sssd/sssd.conf
run chmod 600 /etc/sssd/sssd.conf

# Select SSSD auth profile with home directory creation
run authselect select sssd with-mkhomedir --force

# Enable and start SSSD
run systemctl enable sssd.service
run systemctl restart sssd.service

# Install sudoers drop-in (visudo validates before install)
visudo -cf "${SCRIPT_DIR}/../config/sudoers.d/domain-groups"
run install -m 0440 "${SCRIPT_DIR}/../config/sudoers.d/domain-groups" \
    /etc/sudoers.d/domain-groups

echo "AD join complete for domain ${AD_DOMAIN}"
