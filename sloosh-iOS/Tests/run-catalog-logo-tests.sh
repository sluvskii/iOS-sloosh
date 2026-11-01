#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library \
  Tests/CatalogLogoTests.swift \
  -o "$test_dir/catalog-logo-tests"
"$test_dir/catalog-logo-tests"
