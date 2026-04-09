#!/bin/bash
set -euo pipefail
trap 'echo "ERROR: deploy failed at line $LINENO" >&2' ERR

# Full server deployment pipeline.
# Sources config/env.example variable names; values must be present in the
# environment before running (injected by CI or sourced from a local env file).
#
# Individual scripts can also be run standalone for partial deployments
# or re-runs of a specific stage.
#
# Usage:
#   sudo -E ./scripts/deploy.sh
#   DRY_RUN=true ./scripts/deploy.sh     # Print commands without executing
#
# Stages (can be skipped by setting SKIP_<STAGE>=true):
#   SKIP_BASE_SETUP         Skip base-setup.sh
#   SKIP_AD_JOIN            Skip ad-join.sh
#   SKIP_SATELLITE          Skip satellite-register.sh
#   SKIP_AD_REJOIN_CRON     Skip ad-rejoin-cron.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN="${DRY_RUN:-false}"

[[ "$DRY_RUN" == "true" ]] && echo "=== Dry-run mode: no changes will be made ==="

run_stage() {
    local name="$1"
    local script="$2"
    local skip_var="$3"

    if [[ "${!skip_var:-false}" == "true" ]]; then
        echo "--- Skipping: ${name} (${skip_var}=true)"
        return
    fi

    echo ""
    echo "━━━ Stage: ${name} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    DRY_RUN="$DRY_RUN" bash "${SCRIPT_DIR}/${script}"
    echo "━━━ Done:  ${name}"
}

run_stage "Base setup"       base-setup.sh         SKIP_BASE_SETUP
run_stage "AD join"          ad-join.sh            SKIP_AD_JOIN
run_stage "Satellite"        satellite-register.sh  SKIP_SATELLITE
run_stage "AD rejoin cron"   ad-rejoin-cron.sh     SKIP_AD_REJOIN_CRON

echo ""
echo "Deployment complete."
