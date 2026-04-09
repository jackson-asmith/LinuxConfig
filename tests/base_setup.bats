#!/usr/bin/env bats

load 'test_helper'

setup() {
    setup_mock_bin
    setup_base_env

    # Mock all system commands that base-setup.sh calls
    for cmd in dnf hostnamectl setenforce sysctl systemctl chronyc \
                useradd usermod chmod chown mkdir semanage \
                firewall-cmd sed; do
        mock_command "$cmd"
    done

    # Mock ip to return a predictable address
    cat > "${MOCK_BIN}/ip" <<'EOF'
#!/bin/bash
echo "    inet 192.168.1.100/24 scope global eth0"
EOF
    chmod +x "${MOCK_BIN}/ip"

    # Mock getenforce to return Enforcing by default
    cat > "${MOCK_BIN}/getenforce" <<'EOF'
#!/bin/bash
echo "Enforcing"
EOF
    chmod +x "${MOCK_BIN}/getenforce"
}

teardown() {
    teardown_mock_bin
    unset HOSTNAME FQDN ADMIN_USER DRY_RUN
    unset ADMIN_SSH_KEY SSH_PORT NTP_SERVERS FIREWALL_EXTRA_SERVICES LOGIN_BANNER
}

# ── Variable guards ───────────────────────────────────────────────────────────

@test "fails if HOSTNAME is not set" {
    # unset alone is insufficient — bash re-sets HOSTNAME in every new subprocess.
    # Exporting an empty string causes :? to treat it as unset.
    export HOSTNAME=""
    run bash "${SCRIPTS_DIR}/base-setup.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"HOSTNAME"* ]]
}

@test "fails if FQDN is not set" {
    unset FQDN
    run bash "${SCRIPTS_DIR}/base-setup.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"FQDN"* ]]
}

@test "fails if ADMIN_USER is not set" {
    unset ADMIN_USER
    run bash "${SCRIPTS_DIR}/base-setup.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ADMIN_USER"* ]]
}

# ── SELinux ───────────────────────────────────────────────────────────────────

@test "exits with an error if SELinux is Disabled" {
    cat > "${MOCK_BIN}/getenforce" <<'EOF'
#!/bin/bash
echo "Disabled"
EOF
    run bash "${SCRIPTS_DIR}/base-setup.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"SELinux is disabled"* ]]
}

@test "sets SELinux to enforcing if currently Permissive" {
    cat > "${MOCK_BIN}/getenforce" <<'EOF'
#!/bin/bash
echo "Permissive"
EOF
    run bash "${SCRIPTS_DIR}/base-setup.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY RUN] setenforce 1"* ]]
}

@test "does not modify SELinux if already Enforcing" {
    run bash "${SCRIPTS_DIR}/base-setup.sh"
    [ "$status" -eq 0 ]
    assert_mock_not_called setenforce
}

# ── Dry-run mode ──────────────────────────────────────────────────────────────

@test "dry-run mode prints commands without calling dnf" {
    run bash "${SCRIPTS_DIR}/base-setup.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY RUN]"* ]]
    assert_mock_not_called dnf
}

@test "dry-run mode prints the DRY RUN header" {
    run bash "${SCRIPTS_DIR}/base-setup.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry-run mode enabled"* ]]
}

@test "dry-run completes successfully with all required vars set" {
    run bash "${SCRIPTS_DIR}/base-setup.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Base setup complete"* ]]
}

# ── Non-standard SSH port ─────────────────────────────────────────────────────

@test "dry-run prints semanage port label for non-standard SSH port" {
    export SSH_PORT=2222
    run bash "${SCRIPTS_DIR}/base-setup.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"semanage port"*"2222"* ]]
}

@test "dry-run uses firewall-cmd add-port for non-standard SSH port" {
    export SSH_PORT=2222
    run bash "${SCRIPTS_DIR}/base-setup.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"--add-port=2222/tcp"* ]]
}

# ── Admin SSH key ─────────────────────────────────────────────────────────────

@test "dry-run prints authorized_keys write when ADMIN_SSH_KEY is set" {
    export ADMIN_SSH_KEY="ssh-ed25519 AAAAC3 test@example.com"
    run bash "${SCRIPTS_DIR}/base-setup.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"authorized_keys"* ]]
}

@test "dry-run does not print authorized_keys write when ADMIN_SSH_KEY is unset" {
    unset ADMIN_SSH_KEY
    run bash "${SCRIPTS_DIR}/base-setup.sh"
    [ "$status" -eq 0 ]
    [[ "$output" != *"authorized_keys"* ]]
}

# ── NTP ───────────────────────────────────────────────────────────────────────

@test "dry-run includes pool.ntp.org in chrony config when NTP_SERVERS unset" {
    run bash "${SCRIPTS_DIR}/base-setup.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pool.ntp.org"* ]]
}

@test "dry-run uses custom NTP_SERVERS when provided" {
    export NTP_SERVERS="ntp.example.com"
    run bash "${SCRIPTS_DIR}/base-setup.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ntp.example.com"* ]]
}
