# Security Policy

## Baseline (built into every image)

- **Minimal base** — only curated packages; smaller attack surface
- **No default credentials** — root login via password disabled; wizard forces user password on first boot
- **No listening services** by default (SSH optional during wizard)
- **Signed APT sources** — Debian bookworm and its configured update/security suites
- **sudo, not root** — first user gets sudo; direct root shell discouraged

## Reporting a vulnerability

Do not publish exploit details, credentials, or private logs in a public issue.
Use a verified private contact channel for the maintainer. A dedicated security
mailbox and response SLA have not been established; no placeholder email is a
working reporting channel. Public, non-sensitive hardening suggestions can be
raised through the explicit project issue link.

## Update policy

- Follows Debian stable security updates (bookworm)
- The current `ez-update` script runs package-list refresh, upgrade, and
  autoremove with purge. It does not create snapshots or automatic rollback.
- Breaking security changes documented in CHANGELOG

## Hardening checklist (per release)

- [ ] `/etc/shadow` — no empty/default passwords
- [ ] sshd (if present) — PasswordAuth off unless wizard enabled it
- [ ] No world-writable files in overlay (`find / -perm -0002` audited)
- [ ] setuid binaries enumerated & justified
- [ ] Kernel: stock Debian (proven hardening: ASLR, stack protector on)
- [ ] apt sources: https where available, signed release files
