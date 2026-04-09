#!/usr/bin/env bats

load 'test_helper'

setup() {
    setup_mock_bin
    setup_rejoin_env

    for cmd in yum chown chmod usermod; do
        mock_command "$cmd"
    done

    # Use a temp file for the rejoin script path so we can inspect it
    export REJOIN_SCRIPT="$(mktemp)"
    rm "$REJOIN_SCRIPT"   # Let the script create it

    # Mock crontab to report no existing cron jobs
    cat > "${MOCK_BIN}/crontab" <<'EOF'
#!/bin/bash
echo "crontab $*" >> "${MOCK_BIN}/crontab.log"
# crontab -l returns empty (no existing jobs)
exit 0
EOF
    chmod +x "${MOCK_BIN}/crontab"
}

teardown() {
    teardown_mock_bin
    [[ -f "${REJOIN_SCRIPT:-}" ]] && rm -f "$REJOIN_SCRIPT"
    unset AD_DOMAIN AD_JOIN_USER AD_JOIN_PASS DRY_RUN REJOIN_SCRIPT WHEEL_USER
}

# ── Variable guards ───────────────────────────────────────────────────────────

@test "fails if AD_DOMAIN is not set" {
    unset AD_DOMAIN
    run bash "${SCRIPTS_DIR}/ad-rejoin-cron.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"AD_DOMAIN"* ]]
}

@test "fails if AD_JOIN_USER is not set" {
    unset AD_JOIN_USER
    run bash "${SCRIPTS_DIR}/ad-rejoin-cron.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"AD_JOIN_USER"* ]]
}

@test "fails if AD_JOIN_PASS is not set" {
    unset AD_JOIN_PASS
    run bash "${SCRIPTS_DIR}/ad-rejoin-cron.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"AD_JOIN_PASS"* ]]
}

# ── Dry-run mode ──────────────────────────────────────────────────────────────

@test "dry-run mode prints commands without calling yum" {
    run bash "${SCRIPTS_DIR}/ad-rejoin-cron.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY RUN]"* ]]
    assert_mock_not_called yum
}

@test "dry-run prints cron job entry" {
    run bash "${SCRIPTS_DIR}/ad-rejoin-cron.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"crontab"* ]]
    [[ "$output" == *"0 0 * * *"* ]]
}

@test "dry-run completes successfully with all required vars set" {
    run bash "${SCRIPTS_DIR}/ad-rejoin-cron.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AD rejoin cron setup complete"* ]]
}

# ── Wheel user ────────────────────────────────────────────────────────────────

@test "dry-run prints usermod when WHEEL_USER is set" {
    export WHEEL_USER="svcaccount"
    run bash "${SCRIPTS_DIR}/ad-rejoin-cron.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"usermod"*"svcaccount"* ]]
}

@test "dry-run does not print usermod when WHEEL_USER is not set" {
    unset WHEEL_USER
    run bash "${SCRIPTS_DIR}/ad-rejoin-cron.sh"
    [ "$status" -eq 0 ]
    [[ "$output" != *"usermod"* ]]
}

# ── Idempotency ───────────────────────────────────────────────────────────────

@test "skips cron install if job already exists" {
    cat > "${MOCK_BIN}/crontab" <<EOF
#!/bin/bash
echo "crontab \$*" >> "${MOCK_BIN}/crontab.log"
if [[ "\$1" == "-l" ]]; then
    echo "0 0 * * * ${REJOIN_SCRIPT}"
fi
exit 0
EOF
    export DRY_RUN="false"
    # Also mock the rejoin script execution
    cat > "${MOCK_BIN}/bash" <<'EOF'
#!/bin/bash
exit 0
EOF
    run bash "${SCRIPTS_DIR}/ad-rejoin-cron.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already installed"* ]]
}
