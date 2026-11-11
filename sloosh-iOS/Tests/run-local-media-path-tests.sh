#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
if ! swiftc -parse-as-library -target "$(uname -m)-apple-macosx15.0" \
  sloosh/Sources/Data/Repositories/LocalMediaPathPolicy.swift \
  Tests/LocalMediaPathPolicyTests.swift \
  -o "$test_dir/local-media-path-tests" >"$test_dir/compiler.log" 2>&1; then
  cat "$test_dir/compiler.log"
  head -n 45 "$test_dir/compiler.log" | while IFS= read -r line; do printf '::error::%s\n' "$line"; done
  exit 1
fi
cat "$test_dir/compiler.log"
if "$test_dir/local-media-path-tests" >"$test_dir/tests.log" 2>&1; then
  cat "$test_dir/tests.log"
else
  cat "$test_dir/tests.log"
  head -n 12 "$test_dir/tests.log" | while IFS= read -r line; do printf '::error::%s\n' "$line"; done
  exit 1
fi
