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

: "${AD_DOMAIN:?AD_DOMAIN must be set}"
: "${AD_SERVER:?AD_SERVER must be set}"
: "${KRB5_REALM:?KRB5_REALM must be set}"
: "${AD_JOIN_USER:?AD_JOIN_USER must be set}"
: "${AD_JOIN_PASS:?AD_JOIN_PASS must be set}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Update packages
yum update -y

# Crypto policy required for AD Kerberos compatibility
update-crypto-policies --set DEFAULT:AD-SUPPORT

# Verify LDAP SRV records exist before attempting join
dig -t SRV "_ldap._tcp.${AD_DOMAIN}" +short | grep -q '.' \
    || { echo "ERROR: No LDAP SRV records found for ${AD_DOMAIN}" >&2; exit 1; }

# Install required packages
yum install -y realmd adcli sssd sssd-tools oddjob oddjob-mkhomedir \
    krb5-workstation krb5-libs authselect

# Apply Kerberos config from template
envsubst < "${SCRIPT_DIR}/../config/krb5.conf.tmpl" > /etc/krb5.conf

# Join domain (idempotent)
if ! realm list | grep -q "domain-name: ${AD_DOMAIN}"; then
    echo "Joining domain ${AD_DOMAIN}..."
    echo "$AD_JOIN_PASS" | realm join --user="$AD_JOIN_USER" "$AD_SERVER"
else
    echo "Already joined to ${AD_DOMAIN}, skipping join."
fi

# Apply SSSD config from template
envsubst < "${SCRIPT_DIR}/../config/sssd.conf.tmpl" > /etc/sssd/sssd.conf
chown root:root /etc/sssd/sssd.conf
chmod 600 /etc/sssd/sssd.conf

# Select SSSD auth profile with home directory creation
authselect select sssd with-mkhomedir --force

# Enable and start SSSD
systemctl enable sssd.service
systemctl restart sssd.service

# Install sudoers drop-in (visudo validates before install)
visudo -cf "${SCRIPT_DIR}/../config/sudoers.d/domain-groups"
install -m 0440 "${SCRIPT_DIR}/../config/sudoers.d/domain-groups" \
    /etc/sudoers.d/domain-groups

echo "AD join complete for domain ${AD_DOMAIN}"
