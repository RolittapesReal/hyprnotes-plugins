#!/usr/bin/env bash
# Packs every plugin folder and regenerates index.json.
#   HYPRNOTES  hyprnotes binary (default: hyprnotes)
#   REPO_URL   repository URL used for release asset links
#   OUT        directory holding the plugin folders, index.json and dist/ (default: repository root)
set -euo pipefail

HYPRNOTES=${HYPRNOTES:-hyprnotes}
REPO_URL=${REPO_URL:-https://github.com/RolittapesReal/hyprnotes-plugins}
OUT=${OUT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
HYPRNOTES=$(command -v "$HYPRNOTES") || { echo "hyprnotes binary not found (set HYPRNOTES)" >&2; exit 1; }
OUT=$(cd "$OUT" && pwd)

index="$OUT/index.json"
dist="$OUT/dist"
mkdir -p "$dist"
entries=$(mktemp)
trap 'rm -f "$entries"' EXIT

for manifest in "$OUT"/*/plugin.json; do
    [ -e "$manifest" ] || continue
    dir=$(dirname "$manifest")
    # hyprnotes-markdown-extras is a separate native plugin with its own build and release path.
    [ "$(basename "$dir")" = hyprnotes-markdown-extras ] && continue
    tier=$(jq -r '.tier // empty' "$manifest")
    case "$tier" in script | native) ;; *) continue ;; esac

    "$HYPRNOTES" --check-plugin "$dir" > /dev/null
    id=$(jq -r .id "$manifest")
    version=$(jq -r .version "$manifest")
    asset="$id-$version.hnplugin"
    # --pack-plugin writes into the current directory.
    (cd "$dist" && "$HYPRNOTES" --pack-plugin "$dir" > /dev/null)
    sha=$(sha256sum "$dist/$asset" | cut -d' ' -f1)
    size=$(stat -c %s "$dist/$asset")

    if [ -f "$index" ]; then
        old=$(jq -c --arg id "$id" '.plugins[]? | select(.id == $id)' "$index")
        if [ -n "$old" ]; then
            if [ "$(jq -r .version <<< "$old")" = "$version" ] && [ "$(jq -r .sha256 <<< "$old")" != "$sha" ]; then
                echo "version $version of $id is already released with a different hash; bump the version" >&2
                exit 1
            fi
            jq -r --argjson old "$old" --arg id "$id" --arg v "$version" '
                (.permissions // []) as $new | ($old.permissions // []) as $was |
                (($new - $was) | map("+" + .)) + (($was - $new) | map("-" + .)) |
                if length > 0 then "permissions changed for \($id) \($v): " + join(" ") else empty end' "$manifest" >&2
        fi
    fi

    jq -c --arg url "$REPO_URL/releases/download/$id-$version/$asset" --arg sha "$sha" --argjson size "$size" '
        {id, name, version, author, description, tags: (.tags // []), permissions: (.permissions // []),
         net_hosts: (.net_hosts // []), tier, api, min_app, url: $url, sha256: $sha, size: $size}' "$manifest" >> "$entries"
done

jq -S -n --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{schema: 1, updated: $updated, plugins: ([inputs] | sort_by(.id))}' "$entries" > "$index.tmp"
mv "$index.tmp" "$index"
echo "wrote $index ($(jq '.plugins | length' "$index") plugins)"
