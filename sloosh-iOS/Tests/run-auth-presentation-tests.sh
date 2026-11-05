#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
# Compile the real canonical vector for Canvas image rendering in this macOS CLI.
assets="$test_dir/BrandAssets.xcassets"
bundle="$test_dir/AuthBrandTest.bundle"
mkdir -p "$assets" "$bundle/Contents/Resources"
printf '{"info":{"author":"xcode","version":1}}' > "$assets/Contents.json"
cp -R sloosh/Resources/Assets.xcassets/LogoText.imageset "$assets/"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.sloosh.AuthBrandTest</string>
<key>CFBundleName</key><string>AuthBrandTest</string>
<key>CFBundlePackageType</key><string>BNDL</string>
</dict></plist>
PLIST
if ! xcrun actool "$assets" --compile "$bundle/Contents/Resources" --platform macosx --target-device mac \
  --minimum-deployment-target 15.0 --output-format human-readable-text >"$test_dir/assets.log" 2>&1; then
  cat "$test_dir/assets.log"
  head -n 30 "$test_dir/assets.log" | while IFS= read -r line; do printf '::error::%s\n' "$line"; done
  exit 1
fi
export SLOOSH_AUTH_TEST_ASSETS="$bundle"
if ! swiftc -parse-as-library -target "$(uname -m)-apple-macosx15.0" \
  sloosh/Sources/UI/Shared/CatalogFallbackTitleStyle.swift \
  sloosh/Sources/UI/Shared/BackdropForeground.swift \
  sloosh/Sources/UI/Profile/AuthWordReveal.swift \
  sloosh/Sources/UI/Profile/AuthPhraseLayout.swift \
  sloosh/Sources/UI/Profile/AuthInlineBrand.swift \
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
