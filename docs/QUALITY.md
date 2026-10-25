# EZpenguin Quality Standards

The bar: **the same level of quality and assurance established OSes ship
with** (Debian stable, DietPi, Ubuntu Server LTS) — measured, not claimed.

## Definition of Done (per release)

- [ ] Full pipeline `./build/build.sh all` green from clean state
- [ ] All tests pass (L1–L4, see TESTING.md) — zero failures
- [ ] amd64 rootfs ≤ 700MB installed (stock kernel incl.), ≤ 300MB compressed
- [ ] Live ISO ≤ 500MB
- [ ] Boots to first-boot wizard on BIOS and UEFI — IMG **and** ISO (automated)
- [ ] Interactive wizard smoke test passes (keystroke walkthrough end-to-end)
- [ ] First-boot wizard completes unattended in <5 min on 2-core/2GB VM
- [ ] `dpkg --audit` clean; `apt-get check` clean
- [ ] No default passwords; root login via password disabled
- [ ] All docs accurate: every command in docs exists in the image
- [ ] Version stamped consistently (artifacts, /etc/ezpenguin/version, os-release)
- [ ] Test report archived in artifacts/

## Quality metrics (tracked per build)

| Metric | Target |
|---|---|
| Test pass rate | 100% |
| Rootfs installed size | ≤ 700 MB (incl. stock kernel modules) |
| Compressed rootfs | ≤ 300 MB |
| Live ISO | ≤ 500 MB |
| Package count (base) | ≤ 400 |
| Wizard completion time (2C/2GB) | < 300 s |
| Boot to wizard (QEMU) | < 60 s |
| Open critical bugs | 0 |

## Reliability practices inherited from Debian/DietPi

1. **Stable base** — only Debian stable suites, security patches only
2. **No exotic kernels** — stock Debian kernel; proven drivers
3. **Idempotent scripts** — every system script safe to re-run
4. **Fail-fast installer** — validation before destructive steps
5. **Rollback-safe updates** — `ez-update` uses apt's atomic machinery
6. **Files owned by packages where possible** — overlay files are exceptions, documented

## Release process

```
feature work → tests green → bump version (config/ezpenguin.cfg)
→ full clean build → QA checklist above → tag → artifacts archived
```

No release ships with a failed check. No exceptions.

## Hardening baseline

- Minimal packages (small attack surface)
- No network services enabled by default except ssh *if user opts in*
- root password auth disabled
- firewall available, enabled optionally during wizard
- apt sources pinned with signed repos
