#!/usr/bin/env bash
# test_ezsoft.sh — assert-style self-check for the ez-soft TUI logic.
# Sources rootfs-overlay/usr/local/bin/ez-soft in test mode (EZP_EZSOFT_TEST=1)
# against a tiny fixture catalog and asserts: parse rows/fields, category list,
# selection toggle/select-all, filter matching, render buffer contents, and
# install-plan ordering. No framework; exits non-zero on any failure.
# Needs bash 4+ — on the macOS host it re-execs itself in debian:bookworm.
set -u

if (( BASH_VERSINFO[0] < 4 )); then
    exec docker run --rm \
        -v "$(cd "$(dirname "$0")/.." && pwd):/repo" \
        -w /repo debian:bookworm bash /repo/tests/test_ezsoft.sh
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
EZSOFT="$HERE/../rootfs-overlay/usr/local/bin/ez-soft"
PASS=0 FAIL=0
FAILED=()

ok()  { PASS=$((PASS+1)); echo "ok $PASS - $1"; }
bad() { FAIL=$((FAIL+1)); FAILED+=("$1"); echo "not ok $PASS - $1: $2"; }

assert_eq() { # assert_eq <name> <expected> <actual>
    if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "expected [$2], got [$3]"; fi
}
assert_contains() { # assert_contains <name> <haystack> <needle>
    if [[ "$2" == *"$3"* ]]; then ok "$1"; else bad "$1" "missing [$3] in: $(printf '%s' "$2" | head -c 120)"; fi
}

# ---------------------------------------------------------------- fixture ---
FIXTURE="$(mktemp /tmp/ezsoft-test.XXXXXX)"
trap 'rm -f "$FIXTURE"' EXIT
cat > "$FIXTURE" <<'EOF'
# comment lines must be ignored
alpha|Alpha tool|pkg-alpha|tools|The alpha tool|echo done
beta|Beta server|pkg-beta|server|The beta server|systemctl enable --now beta
gamma|Gamma net|pkg-gamma pkg-extra|network|Gamma network gadget|
delta|Delta dev|pkg-delta|dev|Delta dev things|
EOF

export EZP_EZSOFT_TEST=1
export EZP_CATALOG="$FIXTURE"
# shellcheck disable=SC1090
source "$EZSOFT"

# ------------------------------------------------------- test-mode safety ---
EZP_EZSOFT_TEST=1 bash "$EZSOFT" --selftest >/dev/null 2>&1
assert_eq "test mode prevents interactive main" 0 "$?"

env -u EZP_EZSOFT_TEST TERM=xterm bash "$EZSOFT" </dev/null >/dev/null 2>&1
assert_eq "non-TTY refuses with rc=2 + usage pointer" 2 "$?"

# ---------------------------------------------------------------- parsing ---
parse_catalog_load
assert_eq "parse: entry count" 4 "$(parse_catalog | wc -l | tr -d ' ')"
assert_eq "parse: row has 6 fields" 6 "$(parse_catalog | head -1 | awk -F'\t' '{print NF}')"
assert_eq "parse: postcmd intact (field 6)" "systemctl enable --now beta" \
    "$(parse_catalog '' beta | cut -f6)"
assert_eq "parse: multi-pkg field kept" "pkg-gamma pkg-extra" "$(parse_catalog '' gamma | cut -f3)"
assert_eq "parse: category filter" "delta" "$(parse_catalog dev | cut -f1)"
assert_eq "load: array count" 4 "${#E_NAME[@]}"

assert_eq "catalog_count (all)" 4 "$(catalog_count)"
assert_eq "catalog_count (server)" 1 "$(catalog_count server)"
assert_eq "categories in catalog order" "tools server network dev" \
    "$(catalog_categories | tr '\n' ' ' | sed 's/ $//')"
assert_eq "entry_line round-trip" "alpha|Alpha tool|pkg-alpha|tools|The alpha tool|echo done" \
    "$(entry_line alpha | tr '\t' '|')"

# --------------------------------------------------------------- selection ---
view_rebuild
assert_eq "view: all entries present" 4 "${#VIEW_IDS[@]}"

toggle_select alpha
assert_eq "toggle: select" 1 "$(selection_count)"
toggle_select alpha
assert_eq "toggle: deselect" 0 "$(selection_count)"

select_all_view
assert_eq "select-all: selects whole view" 4 "$(selection_count)"
select_all_view
assert_eq "select-all: toggles back off" 0 "$(selection_count)"

SELECTED[alpha]=1 SELECTED[delta]=1
assert_eq "install_plan: catalog order" "alpha delta" "$(install_plan | tr '\n' ' ' | sed 's/ $//')"

# ----------------------------------------------------------------- filter ---
unset SELECTED; declare -A SELECTED=()
filter_set beta
assert_eq "filter: id substring match" 1 "${#VIEW_IDS[@]}"
assert_eq "filter: matched id" "beta" "${VIEW_IDS[0]}"
filter_set GAMMA
assert_eq "filter: case-insensitive on name/desc" "gamma" "${VIEW_IDS[0]:-}"
filter_clear
assert_eq "filter: clear restores view" 4 "${#VIEW_IDS[@]}"

# cursor clamp after rebuild
CURSOR=99; view_rebuild
assert_eq "view: cursor clamped to last" 3 "$CURSOR"

# ----------------------------------------------------------- render buffer ---
unset SELECTED; declare -A SELECTED=()
ACTIVE_CAT=all FILTER= CURSOR=1 VIEW_OFF=0
SELECTED[alpha]=1 SELECTED[beta]=1
view_rebuild
frame="$(draw_frame)"
assert_contains "render: [x] marker for selected" "$frame" '[x]'
assert_contains "render: entry name shown" "$frame" 'Beta server'
assert_contains "render: unselected marker" "$frame" '[ ]'
assert_contains "render: header selected count" "$frame" '2 selected'
assert_contains "render: detail pane shows cursor entry" "$frame" 'Beta server — The beta server [beta]'
assert_contains "render: detail shows packages" "$frame" 'pkg-beta'
assert_contains "render: detail shows postcmd" "$frame" 'systemctl enable --now beta'
assert_contains "render: footer help" "$frame" 'quit'

# cursor detail follows selection of category view
ACTIVE_CAT=server; CURSOR=0; view_rebuild
assert_eq "view: category restricts view" "beta" "${VIEW_IDS[0]:-}"
frame="$(draw_frame)"
assert_contains "render: category view frame" "$frame" 'Beta server'

# ---------------------------------------------------------------- summary ---
echo
echo "1..$((PASS+FAIL))"
echo "# pass=$PASS fail=$FAIL"
if (( FAIL > 0 )); then
    echo "# FAILED:"
    for f in "${FAILED[@]}"; do echo "#   - $f"; done
    exit 1
fi
echo "# ALL TESTS PASSED"
