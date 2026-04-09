#!/usr/bin/env bats

load 'test_helper'

setup() {
    setup_mock_bin
    # Set all required variables for a full run
    setup_base_env
    setup_ad_env
    setup_satellite_env
    setup_rejoin_env
    export DRY_RUN="true"

    # Mock all system commands called across the four stage scripts so
    # deploy.bats runs cleanly on any OS (Linux, macOS, CI).
    for cmd in dnf yum hostnamectl setenforce sysctl systemctl chronyc \
               useradd usermod chmod chown mkdir semanage firewall-cmd sed \
               update-crypto-policies dig authselect visudo install envsubst \
               rpm; do
        mock_command "$cmd"
    done

    # ip — return a predictable address for base-setup.sh
    cat > "${MOCK_BIN}/ip" <<'EOF'
#!/bin/bash
echo "    inet 192.168.1.100/24 scope global eth0"
EOF
    chmod +x "${MOCK_BIN}/ip"

    # getenforce — report Enforcing so base-setup.sh doesn't abort
    cat > "${MOCK_BIN}/getenforce" <<'EOF'
#!/bin/bash
echo "Enforcing"
EOF
    chmod +x "${MOCK_BIN}/getenforce"

    # realm — report not joined by default
    cat > "${MOCK_BIN}/realm" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "${MOCK_BIN}/realm"

    # subscription-manager — report not registered by default
    cat > "${MOCK_BIN}/subscription-manager" <<'EOF'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    echo "Overall Status: Unknown"
fi
exit 0
EOF
    chmod +x "${MOCK_BIN}/subscription-manager"

    # crontab — report no existing jobs by default
    cat > "${MOCK_BIN}/crontab" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "${MOCK_BIN}/crontab"
}

teardown() {
    teardown_mock_bin
    unset HOSTNAME FQDN ADMIN_USER
    unset AD_DOMAIN AD_SERVER KRB5_REALM AD_JOIN_USER AD_JOIN_PASS
    unset SATELLITE_SERVER SATELLITE_ORG SATELLITE_ACTIVATION_KEY SATELLITE_ENV
    unset DRY_RUN
    unset SKIP_BASE_SETUP SKIP_AD_JOIN SKIP_SATELLITE SKIP_AD_REJOIN_CRON
}

# ── Dry-run passthrough ───────────────────────────────────────────────────────

@test "dry-run mode runs all stages and completes successfully" {
    run bash "${SCRIPTS_DIR}/deploy.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Deployment complete"* ]]
}

@test "dry-run mode prints the DRY RUN header" {
    run bash "${SCRIPTS_DIR}/deploy.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry-run mode"* ]]
}

@test "dry-run output includes all four stage names" {
    run bash "${SCRIPTS_DIR}/deploy.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Base setup"* ]]
    [[ "$output" == *"AD join"* ]]
    [[ "$output" == *"Satellite"* ]]
    [[ "$output" == *"AD rejoin cron"* ]]
}

# ── Skip flags ────────────────────────────────────────────────────────────────

@test "SKIP_BASE_SETUP=true skips the base setup stage" {
    export SKIP_BASE_SETUP="true"
    run bash "${SCRIPTS_DIR}/deploy.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipping: Base setup"* ]]
    [[ "$output" != *"Base setup complete"* ]]
}

@test "SKIP_AD_JOIN=true skips the AD join stage" {
    export SKIP_AD_JOIN="true"
    run bash "${SCRIPTS_DIR}/deploy.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipping: AD join"* ]]
}

@test "SKIP_SATELLITE=true skips the Satellite stage" {
    export SKIP_SATELLITE="true"
    run bash "${SCRIPTS_DIR}/deploy.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipping: Satellite"* ]]
}

@test "SKIP_AD_REJOIN_CRON=true skips the AD rejoin cron stage" {
    export SKIP_AD_REJOIN_CRON="true"
    run bash "${SCRIPTS_DIR}/deploy.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipping: AD rejoin cron"* ]]
}

@test "all stages can be skipped simultaneously" {
    export SKIP_BASE_SETUP="true"
    export SKIP_AD_JOIN="true"
    export SKIP_SATELLITE="true"
    export SKIP_AD_REJOIN_CRON="true"
    run bash "${SCRIPTS_DIR}/deploy.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Deployment complete"* ]]
}
