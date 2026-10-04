#!/usr/bin/env bash
# Runs build-registry.sh against two throwaway plugins. Needs HYPRNOTES to point at a built hyprnotes binary.
set -euo pipefail

: "${HYPRNOTES:?set HYPRNOTES to the hyprnotes binary}"
script=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build-registry.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export OUT="$work" REPO_URL=https://example.org/r

fail() { echo "FAIL: $*" >&2; exit 1; }
check() { local what=$1; shift; "$@" > /dev/null 2>&1 || fail "$what"; }

make_plugin() { # id version permissions-json
    mkdir -p "$work/$1"
    cat > "$work/$1/plugin.json" <<JSON
{"id":"$1","name":"Plugin $1","version":"$2","author":"Test","description":"Test plugin.","api":2,"tier":"script",
 "entry":"main.lua","permissions":$3,"min_app":"0.1.0","tags":["test"]}
JSON
    echo "-- $1" > "$work/$1/main.lua"
}

make_plugin alpha 1.0.0 '["ui"]'
make_plugin beta 1.0.0 '["notes.read"]'
mkdir -p "$work/hyprnotes-markdown-extras" "$work/not-a-plugin"
echo '{"id":"hyprnotes-markdown-extras","tier":"native"}' > "$work/hyprnotes-markdown-extras/plugin.json"

bash "$script" > /dev/null
idx=$work/index.json
check "two entries" jq -e '.plugins | length == 2' "$idx"
check "sorted ids" jq -e '[.plugins[].id] == ["alpha","beta"]' "$idx"
for id in alpha beta; do
    f=$work/dist/$id-1.0.0.hnplugin
    check "$id sha256" jq -e --arg id "$id" --arg s "$(sha256sum "$f" | cut -d' ' -f1)" '.plugins[] | select(.id == $id) | .sha256 == $s' "$idx"
    check "$id size" jq -e --arg id "$id" --argjson n "$(stat -c %s "$f")" '.plugins[] | select(.id == $id) | .size == $n' "$idx"
    check "$id url" jq -e --arg id "$id" '.plugins[] | select(.id == $id) | .url == "https://example.org/r/releases/download/\($id)-1.0.0/\($id)-1.0.0.hnplugin"' "$idx"
done

before=$(jq -c '[.plugins[].sha256]' "$idx")
bash "$script" > /dev/null
[ "$before" = "$(jq -c '[.plugins[].sha256]' "$idx")" ] || fail "re-run changed hashes"

echo "-- changed" >> "$work/alpha/main.lua"
if msg=$(bash "$script" 2>&1); then fail "changed content without a version bump did not abort"; fi
grep -q "bump the version" <<< "$msg" || fail "missing 'bump the version' message: $msg"

sed -i 's/"version":"1.0.0"/"version":"1.1.0"/; s/\["ui"\]/["ui","storage"]/' "$work/alpha/plugin.json"
msg=$(bash "$script" 2>&1) || fail "version bump failed: $msg"
grep -q "permissions changed for alpha 1.1.0: +storage" <<< "$msg" || fail "permission diff not printed: $msg"
check "bumped version indexed" jq -e '.plugins[] | select(.id == "alpha") | .version == "1.1.0"' "$idx"

echo "all registry tests passed"
