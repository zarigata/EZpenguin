# Contributing to EZpenguin

## Ground rules

1. **Match the boring style** — plain bash, fail fast, no cleverness
2. **Test everything you add** — new feature ⇒ new test
3. **Docs are code** — changed behavior ⇒ updated MD file in same change
4. Small, focused changes. One logical thing per commit.

## Workflow

```bash
# 1. build + test your change
./build/build.sh

# 2. verify zero test failures in output

# 3. commit with a clear message
git commit -m "rootfs: add ez-info tool + test"
```

## Code conventions

- Bash: `#!/usr/bin/env bash`, `set -euo pipefail`, double quotes everywhere
- Shell scripts pass `bash -n` and ideally `shellcheck` with no errors
- One package per line in `config/*.list`, comments with `#`
- Overlay files must be idempotent and safe to overwrite

## Adding a package

1. Add to `config/packages-base.list` with `# reason` comment
2. Add/extend a test asserting it's installed and functional
3. Rebuild; confirm size budget (see QUALITY.md) still met

## Adding a tool (`ez-*`)

1. Script in `rootfs-overlay/usr/local/bin/`
2. Document in README + INSTALLATION.md
3. Test: file exists, executable, `bash -n` clean, `--help` exits 0
