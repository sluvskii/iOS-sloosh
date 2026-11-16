#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
if ! swiftc -parse-as-library -target "$(uname -m)-apple-macosx15.0" \
  sloosh/Sources/Data/Models/Models.swift \
  sloosh/Sources/Data/Models/MediaArtworkOverride.swift \
  sloosh/Sources/Data/Models/CatalogArtworkIdentity.swift \
  sloosh/Sources/Data/Models/CatalogSearchPolicy.swift \
  sloosh/Sources/Data/Repositories/CatalogLogoRepository.swift \
  sloosh/Sources/Data/Repositories/ArtworkOverrideStore.swift \
  sloosh/Sources/UI/Search/SearchViewModel.swift \
  Tests/CatalogLogoTestSupport.swift \
  Tests/CatalogSearchTests.swift \
  -o "$test_dir/catalog-search-tests" >"$test_dir/compiler.log" 2>&1; then
  cat "$test_dir/compiler.log"
  head -n 35 "$test_dir/compiler.log" | while IFS= read -r line; do printf '::error::%s\n' "$line"; done
  exit 1
fi
cat "$test_dir/compiler.log"
"$test_dir/catalog-search-tests"
