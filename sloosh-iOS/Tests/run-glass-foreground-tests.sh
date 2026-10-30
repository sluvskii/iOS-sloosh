#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
# Compiler/test diagnostics must also reach Actions annotations: raw log downloads
# are not always available in the development environment. These are UI-only tests.
if ! swiftc -parse-as-library -target "$(uname -m)-apple-macosx15.0" \
  sloosh/Sources/UI/Shared/BackdropForeground.swift \
  sloosh/Sources/UI/Shared/GlassForeground.swift \
  Tests/GlassForegroundTests.swift \
  -o "$test_dir/glass-foreground-tests" >"$test_dir/compiler.log" 2>&1; then
  cat "$test_dir/compiler.log"
  head -n 30 "$test_dir/compiler.log" | while IFS= read -r line; do
    printf '::error::%s\n' "$line"
  done
  exit 1
fi
cat "$test_dir/compiler.log"
if "$test_dir/glass-foreground-tests" >"$test_dir/test.log" 2>&1; then
  cat "$test_dir/test.log"
else
  cat "$test_dir/test.log"
  head -n 10 "$test_dir/test.log" | while IFS= read -r line; do
    printf '::error::%s\n' "$line"
  done
  exit 1
fi
