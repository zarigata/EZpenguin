#!/usr/bin/env bash
# push-via-api.sh — sync working tree to GitHub main via git data API.
# Handles adds/updates AND deletions (sha:null entries). Bash 3.2 compatible.
set -euo pipefail
REPO="zarigata/EZpenguin"
API="repos/$REPO"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

BASE=$(gh api "$API/git/ref/heads/main" --jq .object.sha)
BASE_TREE=$(gh api "$API/git/commits/$BASE" --jq .tree.sha)
echo "base: $BASE"

# local: "<mode> <path>" — stage-0 entries only
git ls-files -s | awk '$3=="0"{print $1" "$4}' | sort > "$WORK/local"
# remote: "<mode> <path>" — blobs only (paths may contain spaces; join for compare)
gh api "$API/git/trees/$BASE_TREE?recursive=1" \
    --jq '.tree[] | select(.type=="blob") | "\(.mode)|\(.path)"' | sort > "$WORK/remote"
awk '{print $1"|"$2}' "$WORK/local" | sort > "$WORK/local.j"

ENTRIES="[]"
# adds/updates: everything local
while read -r mode path; do
    BLOB=$(jq -n --rawfile c "$path" '{content:$c,encoding:"utf-8"}' \
        | gh api "$API/git/blobs" --input - --jq .sha)
    ENTRIES=$(jq -c --arg p "$path" --arg m "$mode" --arg s "$BLOB" \
        '. + [{path:$p, mode:$m, type:"blob", sha:$s}]' <<< "$ENTRIES")
done < <(awk '{print $1" "$2}' "$WORK/local")

# deletions: remote paths not present locally (compare on path field)
DELETED=0
while IFS='|' read -r rmode rpath; do
    if ! awk -v p="$rpath" 'BEGIN{FS="|"} $2==p{found=1} END{exit !found}' "$WORK/local.j"; then
        ENTRIES=$(jq -c --arg p "$rpath" \
            '. + [{path:$p, mode:"100644", type:"blob", sha:null}]' <<< "$ENTRIES")
        DELETED=$((DELETED+1))
        echo "  deleting: $rpath"
    fi
done < "$WORK/remote"

echo "entries: $(jq length <<< "$ENTRIES") (deletions: $DELETED)"
TREE=$(jq -n --arg b "$BASE_TREE" --argjson t "$ENTRIES" '{base_tree:$b, tree:$t}' \
    | gh api "$API/git/trees" --input - --jq .sha)
COMMIT=$(jq -n --arg m "sync: $(git log -1 --pretty=%s)" \
    --arg t "$TREE" --arg p "$BASE" '{message:$m, tree:$t, parents:[$p]}' \
    | gh api "$API/git/commits" --input - --jq .sha)
gh api "$API/git/refs/heads/main" -X PATCH -f sha="$COMMIT" --jq .object.sha
echo "pushed commit: $COMMIT"
