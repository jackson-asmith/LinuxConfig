#!/usr/bin/env bats

load 'test_helper'

setup() {
    setup_mock_bin
    setup_satellite_env

    for cmd in rpm yum systemctl; do
        mock_command "$cmd"
    done

    # Mock subscription-manager to report not registered by default
    cat > "${MOCK_BIN}/subscription-manager" <<'EOF'
#!/bin/bash
echo "subscription-manager $*" >> "${MOCK_BIN}/subscription-manager.log"
if [[ "$1" == "status" ]]; then
    echo "Overall Status: Unknown"
fi
exit 0
EOF
    chmod +x "${MOCK_BIN}/subscription-manager"
}

teardown() {
    teardown_mock_bin
    unset SATELLITE_SERVER SATELLITE_ORG SATELLITE_ACTIVATION_KEY SATELLITE_ENV DRY_RUN
}

# ── Variable guards ───────────────────────────────────────────────────────────

@test "fails if SATELLITE_SERVER is not set" {
    unset SATELLITE_SERVER
    run bash "${SCRIPTS_DIR}/satellite-register.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"SATELLITE_SERVER"* ]]
}

@test "fails if SATELLITE_ORG is not set" {
    unset SATELLITE_ORG
    run bash "${SCRIPTS_DIR}/satellite-register.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"SATELLITE_ORG"* ]]
}

@test "fails if SATELLITE_ACTIVATION_KEY is not set" {
    unset SATELLITE_ACTIVATION_KEY
    run bash "${SCRIPTS_DIR}/satellite-register.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"SATELLITE_ACTIVATION_KEY"* ]]
}

# ── Dry-run mode ──────────────────────────────────────────────────────────────

@test "dry-run mode prints commands without calling rpm" {
    run bash "${SCRIPTS_DIR}/satellite-register.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY RUN]"* ]]
    assert_mock_not_called rpm
}

@test "dry-run prints subscription-manager register command" {
    run bash "${SCRIPTS_DIR}/satellite-register.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"subscription-manager register"* ]]
    [[ "$output" == *"${SATELLITE_ORG}"* ]]
}

@test "dry-run does not print activation key in output" {
    run bash "${SCRIPTS_DIR}/satellite-register.sh"
    [ "$status" -eq 0 ]
    [[ "$output" != *"${SATELLITE_ACTIVATION_KEY}"* ]]
}

@test "dry-run completes successfully with all required vars set" {
    run bash "${SCRIPTS_DIR}/satellite-register.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Satellite registration complete"* ]]
}

@test "defaults SATELLITE_ENV to Library when not set" {
    unset SATELLITE_ENV
    run bash "${SCRIPTS_DIR}/satellite-register.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Library"* ]]
}

# ── Idempotency ───────────────────────────────────────────────────────────────

@test "skips registration if already registered and current" {
    cat > "${MOCK_BIN}/subscription-manager" <<'EOF'
#!/bin/bash
echo "subscription-manager $*" >> "${MOCK_BIN}/subscription-manager.log"
if [[ "$1" == "status" ]]; then
    echo "Overall Status: Current"
fi
exit 0
EOF
    export DRY_RUN="false"
    run bash "${SCRIPTS_DIR}/satellite-register.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already registered"* ]]
}
