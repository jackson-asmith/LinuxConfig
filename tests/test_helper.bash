# Shared setup and mock utilities for all bats test files.
#
# Usage in a .bats file:
#   load 'test_helper'

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
SCRIPTS_DIR="${REPO_ROOT}/scripts"

# Creates a temp directory and prepends it to PATH so mock commands take
# precedence over real system binaries for the duration of a test.
setup_mock_bin() {
    MOCK_BIN="$(mktemp -d)"
    export PATH="${MOCK_BIN}:${PATH}"
}

teardown_mock_bin() {
    [[ -d "${MOCK_BIN:-}" ]] && rm -rf "$MOCK_BIN"
}

# Creates a mock command that records its arguments to a log file and
# exits successfully. Use assert_mock_called to verify invocations.
#
# Usage:
#   mock_command dnf
#   mock_command systemctl
mock_command() {
    local cmd="$1"
    cat > "${MOCK_BIN}/${cmd}" <<EOF
#!/bin/bash
echo "${cmd} \$*" >> "${MOCK_BIN}/${cmd}.log"
exit 0
EOF
    chmod +x "${MOCK_BIN}/${cmd}"
}

# Asserts that a mock command was called with arguments matching a pattern.
#
# Usage:
#   assert_mock_called dnf "install -y chrony"
assert_mock_called() {
    local cmd="$1"
    local pattern="$2"
    local logfile="${MOCK_BIN}/${cmd}.log"

    if [[ ! -f "$logfile" ]]; then
        echo "ASSERT FAILED: '${cmd}' was never called" >&2
        return 1
    fi
    if ! grep -q "$pattern" "$logfile"; then
        echo "ASSERT FAILED: '${cmd}' was not called with '${pattern}'" >&2
        echo "Actual calls:" >&2
        cat "$logfile" >&2
        return 1
    fi
}

# Asserts that a mock command was never called.
assert_mock_not_called() {
    local cmd="$1"
    local logfile="${MOCK_BIN}/${cmd}.log"
    if [[ -f "$logfile" ]]; then
        echo "ASSERT FAILED: '${cmd}' was called but should not have been" >&2
        cat "$logfile" >&2
        return 1
    fi
}

# Sets required base-setup variables with safe defaults for testing.
setup_base_env() {
    export HOSTNAME="testhost"
    export FQDN="testhost.example.com"
    export ADMIN_USER="testadmin"
    export DRY_RUN="true"
}

# Sets required AD join variables with safe defaults for testing.
setup_ad_env() {
    export AD_DOMAIN="example.com"
    export AD_SERVER="dc-01.example.com"
    export KRB5_REALM="EXAMPLE.COM"
    export AD_JOIN_USER="linux_join"
    export AD_JOIN_PASS="testpass"
    export DRY_RUN="true"
}

# Sets required Satellite variables with safe defaults for testing.
setup_satellite_env() {
    export SATELLITE_SERVER="satellite.example.com"
    export SATELLITE_ORG="TestOrg"
    export SATELLITE_ACTIVATION_KEY="test-key"
    export DRY_RUN="true"
}

# Sets required AD rejoin cron variables with safe defaults for testing.
setup_rejoin_env() {
    export AD_DOMAIN="example.com"
    export AD_JOIN_USER="linux_join"
    export AD_JOIN_PASS="testpass"
    export DRY_RUN="true"
}
