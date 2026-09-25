#!/usr/bin/env bash
# Point sources.json at the newest nightly Delta. No-op when already current.
# Each arch's hash comes from prefetching the very bytes the API serves for
# that version, so the fixed-output src in package.nix is correct by
# construction.
set -euo pipefail

api=https://delta.dev/api/releases/nightly
sources=${1:-sources.json}

# nix system -> the arch name delta.dev's API expects
declare -A arches=([x86_64-linux]=x86_64 [aarch64-linux]=aarch64)

asset() { curl -fsSL "$api/$1/asset?asset=delta&os=linux&arch=$2"; }

current=$(jq -er .version "$sources")
latest=$(asset latest x86_64 | jq -er .version)

if [ "$latest" = "$current" ]; then
  echo "delta is up to date at $current"
  exit 0
fi

echo "delta: $current -> $latest"
next=$(jq --arg v "$latest" '.version = $v' "$sources")
for system in "${!arches[@]}"; do
  arch=${arches[$system]}
  url=$(asset "$latest" "$arch" | jq -er .url)
  hash=$(nix store prefetch-file --json --name "delta-linux-$arch-$latest.tar.gz" "$url" | jq -er .hash)
  echo "  $system: $hash"
  next=$(jq --arg s "$system" --arg h "$hash" '.hashes[$s] = $h' <<<"$next")
done
printf '%s\n' "$next" >"$sources"
