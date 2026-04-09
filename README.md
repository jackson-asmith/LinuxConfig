# LinuxConfig

A modular server build pipeline for bootstrapping RHEL-based Linux hosts into an Active Directory environment with centralized subscription management.

## Pipeline stages

| Script | Description |
|--------|-------------|
| `scripts/base-setup.sh` | Hostname, package updates, SSH hardening, admin user creation |
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

## Config templates

`config/krb5.conf.tmpl` and `config/sssd.conf.tmpl` are applied via `envsubst` during the AD join stage — edit these to adjust Kerberos or SSSD behaviour without touching the scripts themselves.

## Linting

The included GitHub Actions workflow (`.github/workflows/lint.yml`) runs on every push and pull request:

- **ShellCheck** — static analysis on all scripts
- **sudoers validation** — `visudo -c` on the sudoers drop-in
- **Template coverage** — verifies all template variables are documented in `env.example`
