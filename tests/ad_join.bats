#!/usr/bin/env bats

load 'test_helper'

setup() {
    setup_mock_bin
    setup_ad_env

    for cmd in yum update-crypto-policies dig authselect systemctl \
                visudo install envsubst chown chmod; do
        mock_command "$cmd"
    done

    # Mock realm to report not joined by default
    cat > "${MOCK_BIN}/realm" <<'EOF'
#!/bin/bash
echo "realm $*" >> "${MOCK_BIN}/realm.log"
# realm list returns empty (not joined)
exit 0
EOF
    chmod +x "${MOCK_BIN}/realm"
}

teardown() {
    teardown_mock_bin
    unset AD_DOMAIN AD_SERVER KRB5_REALM AD_JOIN_USER AD_JOIN_PASS DRY_RUN
}

# ── Variable guards ───────────────────────────────────────────────────────────

@test "fails if AD_DOMAIN is not set" {
    unset AD_DOMAIN
    run bash "${SCRIPTS_DIR}/ad-join.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"AD_DOMAIN"* ]]
}

@test "fails if AD_SERVER is not set" {
    unset AD_SERVER
    run bash "${SCRIPTS_DIR}/ad-join.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"AD_SERVER"* ]]
}

@test "fails if KRB5_REALM is not set" {
    unset KRB5_REALM
    run bash "${SCRIPTS_DIR}/ad-join.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"KRB5_REALM"* ]]
}

@test "fails if AD_JOIN_USER is not set" {
    unset AD_JOIN_USER
    run bash "${SCRIPTS_DIR}/ad-join.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"AD_JOIN_USER"* ]]
}

@test "fails if AD_JOIN_PASS is not set" {
    unset AD_JOIN_PASS
    run bash "${SCRIPTS_DIR}/ad-join.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"AD_JOIN_PASS"* ]]
}

# ── Dry-run mode ──────────────────────────────────────────────────────────────

@test "dry-run mode prints commands without calling yum" {
    run bash "${SCRIPTS_DIR}/ad-join.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY RUN]"* ]]
    assert_mock_not_called yum
}

@test "dry-run prints realm join command" {
    run bash "${SCRIPTS_DIR}/ad-join.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"realm join"* ]]
    [[ "$output" == *"${AD_JOIN_USER}"* ]]
    [[ "$output" == *"${AD_SERVER}"* ]]
}

@test "dry-run does not print AD_JOIN_PASS in output" {
    run bash "${SCRIPTS_DIR}/ad-join.sh"
    [ "$status" -eq 0 ]
    [[ "$output" != *"${AD_JOIN_PASS}"* ]]
}

@test "dry-run completes successfully with all required vars set" {
    run bash "${SCRIPTS_DIR}/ad-join.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AD join complete"* ]]
}

# ── Idempotency ───────────────────────────────────────────────────────────────

@test "skips realm join if already joined to domain" {
    # Override realm mock to report already joined
    cat > "${MOCK_BIN}/realm" <<EOF
#!/bin/bash
echo "realm \$*" >> "${MOCK_BIN}/realm.log"
if [[ "\$1" == "list" ]]; then
    echo "  domain-name: ${AD_DOMAIN}"
fi
exit 0
EOF
    export DRY_RUN="false"
    run bash "${SCRIPTS_DIR}/ad-join.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Already joined"* ]]
}
