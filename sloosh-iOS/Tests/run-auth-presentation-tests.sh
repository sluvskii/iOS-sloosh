#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
if ! swiftc -parse-as-library -target "$(uname -m)-apple-macosx15.0" \
  sloosh/Sources/UI/Shared/CatalogFallbackTitleStyle.swift \
  sloosh/Sources/UI/Shared/BackdropForeground.swift \
  sloosh/Sources/UI/Profile/AuthWordReveal.swift \
  sloosh/Sources/UI/Profile/AuthPhraseLayout.swift \
  sloosh/Sources/UI/Profile/AuthCinematicBackground.swift \
  Tests/AuthPresentationTests.swift \
  -o "$test_dir/auth-presentation-tests" >"$test_dir/compiler.log" 2>&1; then
  cat "$test_dir/compiler.log"
  head -n 45 "$test_dir/compiler.log" | while IFS= read -r line; do printf '::error::%s\n' "$line"; done
  exit 1
fi
cat "$test_dir/compiler.log"
if "$test_dir/auth-presentation-tests" >"$test_dir/tests.log" 2>&1; then
  cat "$test_dir/tests.log"
else
  cat "$test_dir/tests.log"
  head -n 12 "$test_dir/tests.log" | while IFS= read -r line; do printf '::error::%s\n' "$line"; done
  exit 1
fi
