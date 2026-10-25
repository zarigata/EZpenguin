# Security Policy

## Baseline (built into every image)

- **Minimal base** — only curated packages; smaller attack surface
- **No default credentials** — root login via password disabled; wizard forces user password on first boot
- **No listening services** by default (SSH optional during wizard)
- **Pinned signed APT sources** — Debian official + security suites
- **sudo, not root** — first user gets sudo; direct root shell discouraged

## Reporting a vulnerability

Email: security@ezpenguin.org (placeholder until domain live).

- We commit to acknowledging reports within 72 hours
- Fixes for critical issues ship within 7 days when feasible
- Credits in CHANGELOG unless anonymity requested

Please do NOT open public issues for security problems.

## Update policy

- Follows Debian stable security updates (bookworm)
- `ez-update` applies dist-upgrade with apt's atomic, rollback-safe mechanics
- Breaking security changes documented in CHANGELOG

## Hardening checklist (per release)

- [ ] `/etc/shadow` — no empty/default passwords
- [ ] sshd (if present) — PasswordAuth off unless wizard enabled it
- [ ] No world-writable files in overlay (`find / -perm -0002` audited)
- [ ] setuid binaries enumerated & justified
- [ ] Kernel: stock Debian (proven hardening: ASLR, stack protector on)
- [ ] apt sources: https where available, signed release files
