# LinuxConfig

A modular server build pipeline for bootstrapping RHEL-based Linux hosts into an Active Directory environment with centralized subscription management.

## Pipeline stages

| Script | Description |
|--------|-------------|
| `scripts/base-setup.sh` | Hostname, package updates, NTP, SELinux, SSH hardening, firewall, sysctl, auditd, PAM lockout, automatic updates, login banner |
| `scripts/ad-join.sh` | AD domain join, Kerberos, SSSD, and sudo configuration |
| `scripts/satellite-register.sh` | Red Hat Satellite registration and remote management tooling |
| `scripts/ad-rejoin-cron.sh` | Daily cron job to recover domain membership if lost |

Run all stages in sequence via:

```bash
sudo -E ./scripts/deploy.sh
```

Individual scripts can be run standalone for partial deployments or re-runs of a specific stage.

## Configuration

Copy `config/env.example` and fill in values for your environment:

```bash
cp config/env.example config/env
# edit config/env
set -a && source config/env && set +a
sudo -E ./scripts/deploy.sh
```

For CI/CD, configure values as GitHub Actions secrets and variables (see `config/env.example` for the full list and which should be treated as secrets).

## Dry-run mode

All scripts support `DRY_RUN=true`, which prints every side-effectful command without executing it. Useful for validating configuration before running against a real host:

```bash
DRY_RUN=true ./scripts/deploy.sh
```

Individual stages can also be skipped:

```bash
SKIP_AD_JOIN=true SKIP_SATELLITE=true DRY_RUN=true ./scripts/deploy.sh
```

## Config templates

`config/krb5.conf.tmpl` and `config/sssd.conf.tmpl` are applied via `envsubst` during the AD join stage — edit these to adjust Kerberos or SSSD behaviour without touching the scripts themselves.

## Testing

Tests are written with [bats-core](https://github.com/bats-core/bats-core) and run in CI on every push and pull request.

Install bats-core locally and run the suite:

```bash
# macOS
brew install bats-core

# RHEL/Fedora
dnf install bats

# Run all tests
bats tests/

# Run a specific file
bats tests/base_setup.bats
```

### What is and isn't tested

Tests run entirely in dry-run mode with mocked system commands — no RHEL host, AD environment, or Satellite server is required.

| Test file | Coverage |
|-----------|----------|
| `tests/base_setup.bats` | Variable guards, SELinux state handling, dry-run output, SSH port branching, NTP config, SSH key handling |
| `tests/ad_join.bats` | Variable guards, dry-run output, secret redaction, idempotent domain join |
| `tests/satellite_register.bats` | Variable guards, dry-run output, secret redaction, idempotent registration, default env |
| `tests/ad_rejoin_cron.bats` | Variable guards, dry-run output, cron idempotency, wheel user branching |
| `tests/deploy.bats` | Dry-run passthrough, per-stage skip flags |

End-to-end integration testing (verifying system state post-deploy) requires a live RHEL host and is not currently automated. [Testinfra](https://testinfra.readthedocs.io/) is the recommended tool for adding that layer when an environment is available.

## Linting

The included GitHub Actions workflow (`.github/workflows/lint.yml`) runs on every push and pull request:

- **ShellCheck** — static analysis on all scripts
- **sudoers validation** — `visudo -c` on the sudoers drop-in
- **Template coverage** — verifies all template variables are documented in `env.example`
- **bats-core** — unit tests for all scripts
