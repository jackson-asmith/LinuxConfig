#!/bin/bash
set -euo pipefail
trap 'echo "ERROR: script failed at line $LINENO" >&2' ERR

# Registers the host with a Red Hat Satellite 6/7 server using
# subscription-manager, then installs remote host management tooling.
#
# Remote management tooling is selected automatically based on what the
# Satellite server makes available:
#   - rhc + rhc-worker-playbook  (Satellite 6.11+, preferred)
#   - katello-agent + goferd     (Satellite 6.7-6.10, legacy fallback)
#
# Required variables:
#   SATELLITE_SERVER          Satellite server FQDN        (e.g. satellite.example.com)
#   SATELLITE_ORG             Satellite organization name  (e.g. MyOrg)
#   SATELLITE_ACTIVATION_KEY  Activation key name          (e.g. rhel9-base)
#
# Optional variables:
#   SATELLITE_ENV             Content view environment     (default: Library)
#   DRY_RUN                   Set to "true" to print commands without executing

: "${SATELLITE_SERVER:?SATELLITE_SERVER must be set}"
: "${SATELLITE_ORG:?SATELLITE_ORG must be set}"
: "${SATELLITE_ACTIVATION_KEY:?SATELLITE_ACTIVATION_KEY must be set}"

SATELLITE_ENV="${SATELLITE_ENV:-Library}"
DRY_RUN="${DRY_RUN:-false}"

run() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] $*"
    else
        "$@"
    fi
}

[[ "$DRY_RUN" == "true" ]] && echo "--- Dry-run mode enabled: no changes will be made ---"

# Install the Satellite CA certificate. This configures subscription-manager
# to trust the Satellite server and points /etc/rhsm/rhsm.conf at it.
run rpm -Uvh --force \
    "http://${SATELLITE_SERVER}/pub/katello-ca-consumer-latest.noarch.rpm"

# Register with Satellite — idempotency check runs regardless of dry-run mode.
if subscription-manager status 2>/dev/null | grep -q 'Overall Status: Current'; then
    echo "System already registered and current, skipping registration."
elif [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] subscription-manager register --org=${SATELLITE_ORG} --activationkey=*** --environment=${SATELLITE_ENV}"
else
    subscription-manager register \
        --org="${SATELLITE_ORG}" \
        --activationkey="${SATELLITE_ACTIVATION_KEY}" \
        --environment="${SATELLITE_ENV}" \
        --force
fi

# Install remote management tooling. Prefer rhc (Satellite 6.11+); fall back
# to katello-agent if rhc is not available from this Satellite server.
if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] yum install rhc or katello-agent (detected at runtime)"
elif yum info rhc &>/dev/null 2>&1; then
    echo "Installing rhc (Satellite 6.11+)..."
    yum install -y rhc rhc-worker-playbook
    rhc connect \
        --activation-key="${SATELLITE_ACTIVATION_KEY}" \
        --organization="${SATELLITE_ORG}"
else
    echo "rhc not available, installing katello-agent (Satellite 6.7-6.10)..."
    yum install -y katello-agent
    systemctl enable --now goferd
fi

# Confirm final subscription state
if [[ "$DRY_RUN" != "true" ]]; then
    subscription-manager refresh
    subscription-manager status
fi

echo "Satellite registration complete (org: ${SATELLITE_ORG})"
