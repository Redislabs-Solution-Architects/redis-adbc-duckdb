#!/usr/bin/env bash
# Write an extension release version (vX.Y.Z or vX.Y.Z-N) into the build
# metadata (EXTENSION_VERSION) and the extension's Version().
set -euo pipefail
version=${1:?usage: stamp_version.sh vX.Y.Z[-N]}
[[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || { echo "invalid release version: $version" >&2; exit 2; }
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
config="$root/extension_config.cmake"
header="$root/duckdb-extension/include/redis_adbc_extension.hpp"
sed -i.orig -E "s/EXTENSION_VERSION v[^ )]+/EXTENSION_VERSION $version/" "$config"
sed -i.orig -E "s/(Version\(\) const override \{ return \")v[^\"]+/\1$version/" "$header"
rm "$config.orig" "$header.orig"
grep -q "EXTENSION_VERSION $version$" "$config" || { echo "EXTENSION_VERSION not stamped" >&2; exit 1; }
grep -q "return \"$version\";" "$header" || { echo "Version() not stamped" >&2; exit 1; }
