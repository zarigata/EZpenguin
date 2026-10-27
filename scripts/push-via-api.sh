#!/usr/bin/env bash
# push-via-api.sh — sync working tree to GitHub main via git data API.
set -euo pipefail
REPO="zarigata/EZpenguin"
API="repos/$REPO"

BASE=$(gh api "$API/git/ref/heads/main" --jq .object.sha)
echo "base: $BASE"

ENTRIES="[]"
while read -r mode _sha stage path; do
    [[ "$stage" == "0" ]] || continue
    BLOB=$(jq -n --rawfile c "$path" '{content:$c,encoding:"utf-8"}' \
        | gh api "$API/git/blobs" --input - --jq .sha)
    ENTRIES=$(jq -c --arg p "$path" --arg m "$mode" --arg s "$BLOB" \
        '. + [{path:$p, mode:$m, type:"blob", sha:$s}]' <<< "$ENTRIES")
done < <(git ls-files -s)

echo "files: $(jq length <<< "$ENTRIES")"
TREE=$(jq -n --arg b "$BASE" --argjson t "$ENTRIES" '{base_tree:$b, tree:$t}' \
    | gh api "$API/git/trees" --input - --jq .sha)
COMMIT=$(jq -n --arg m "v0.4.1: one-liner online installer, GitHub Pages, README, catalog 61, banner fix" \
    --arg t "$TREE" --arg p "$BASE" '{message:$m, tree:$t, parents:[$p]}' \
    | gh api "$API/git/commits" --input - --jq .sha)
gh api "$API/git/refs/heads/main" -X PATCH -f sha="$COMMIT" --jq .object.sha
echo "pushed commit: $COMMIT"
