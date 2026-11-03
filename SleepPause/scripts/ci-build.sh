#!/usr/bin/env bash
# GitHub Actions build for SleepPause.
# Regenerates the Xcode project, runs the logic checks, builds the iOS app
# (embedded widget + watch app) for the generic simulator and a generic device,
# builds the watch scheme for the watchOS simulator, and — when those builds
# succeed — produces an unsigned .ipa / .xcarchive.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
LOGS="$ROOT/ci-logs"
BUILD="$ROOT/build"
mkdir -p "$LOGS" "$BUILD"

{
  echo "xcode-select: $(xcode-select -p)"
  xcodebuild -version
  swift --version
  xcodegen --version
} | tee "$LOGS/environment.txt"

echo "=== xcodegen ==="
xcodegen generate | tee "$LOGS/xcodegen.log"

# BASE_BUNDLE_ID stays the placeholder. CI never rewrites it.
grep -q 'com.example.sleeppause' SleepPause.xcodeproj/project.pbxproj
grep -q 'BASE_BUNDLE_ID: com.example.sleeppause' project.yml

echo "=== logic checks (project test harness; there is no XCTest target) ==="
set +e
set +o pipefail
SWIFTC="$(xcrun -f swiftc)" SWIFT_SDK="$(xcrun --sdk macosx --show-sdk-path)" bash scripts/linux-check.sh 2>&1 | tee "$LOGS/logic-checks.log"
logic_status=${PIPESTATUS[0]}
set -o pipefail
set -e
if [[ "$logic_status" -ne 0 ]]; then
  echo "logic checks failed ($logic_status)"
  exit "$logic_status"
fi

SIGNING=(
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
  CODE_SIGN_IDENTITY=
  ONLY_ACTIVE_ARCH=NO
  COMPILER_INDEX_STORE_ENABLE=NO
)

run_build() {
  local name="$1"
  shift
  echo "=== $name ==="
  set +e
  set +o pipefail
  xcodebuild "$@" "${SIGNING[@]}" -derivedDataPath "$BUILD/DerivedData" 2>&1 | tee "$LOGS/$name.log"
  local status=${PIPESTATUS[0]}
  set -o pipefail
  set -e
  if [[ "$status" -ne 0 ]]; then
    echo "FAILED $name (exit $status)"
    grep -E "error:|fatal error:" "$LOGS/$name.log" | head -n 200 > "$LOGS/$name.errors.txt" || true
    return "$status"
  fi
  echo "OK $name"
}

build_all() {
  local failed=0
  run_build ios-simulator \
    -project SleepPause.xcodeproj \
    -scheme SleepPause \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug \
    build || failed=1

run_build ios-device \
  -project SleepPause.xcodeproj \
  -scheme SleepPause \
  -destination 'generic/platform=iOS' \
  -configuration Debug \
  build || failed=1

  run_build watch-simulator \
    -project SleepPause.xcodeproj \
    -scheme SleepPauseWatch \
    -destination 'generic/platform=watchOS Simulator' \
    -configuration Debug \
    build || failed=1

  return "$failed"
}

set +e
build_all
fail=$?
set -e

if [[ "$fail" -ne 0 ]] && grep -q "must be embedded in the parent app bundle's PlugIns directory" "$LOGS"/*.log; then
  echo "=== applying scripts/patch-watch-embed-plugins.sh and retrying ==="
  bash scripts/patch-watch-embed-plugins.sh | tee "$LOGS/embed-patch.log"
  set +e
  build_all
  fail=$?
  set -e
fi

if [[ "$fail" -ne 0 ]]; then
  echo "One or more builds failed. Skipping unsigned archive."
  grep -E "warning:" "$LOGS"/*.log | head -n 400 > "$LOGS/warnings.txt" || true
  exit 1
fi

echo "=== unsigned archive (device) ==="
set +e
set +o pipefail
xcodebuild \
  -project SleepPause.xcodeproj \
  -scheme SleepPause \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  -archivePath "$BUILD/SleepPause.xcarchive" \
  -derivedDataPath "$BUILD/DerivedData" \
  archive \
  "${SIGNING[@]}" \
  VALIDATE_PRODUCT=NO \
  2>&1 | tee "$LOGS/ios-archive.log"
archive_status=${PIPESTATUS[0]}
set -o pipefail
set -e

APP=""
if [[ "$archive_status" -eq 0 && -d "$BUILD/SleepPause.xcarchive/Products/Applications/SleepPause.app" ]]; then
  APP="$BUILD/SleepPause.xcarchive/Products/Applications/SleepPause.app"
else
  echo "Archive did not produce an app (exit $archive_status). Falling back to the device build product."
  APP="$(find "$BUILD/DerivedData" -type d -path '*iphoneos*/SleepPause.app' | head -n 1 || true)"
fi

if [[ -n "${APP}" && -d "${APP}" ]]; then
  STAGE="$BUILD/ipa-stage"
  rm -rf "$STAGE"
  mkdir -p "$STAGE/Payload"
  cp -R "$APP" "$STAGE/Payload/SleepPause.app"
  (cd "$STAGE" && zip -qry "$BUILD/SleepPause-unsigned.ipa" Payload)
  echo "Wrote $BUILD/SleepPause-unsigned.ipa from $APP"
else
  echo "No .app found to package."
fi

cat > "$BUILD/UNSIGNED.txt" << 'EOF'
SleepPause unsigned iOS build
=============================

SleepPause-unsigned.ipa and SleepPause.xcarchive (when present) are not signed.
CODE_SIGNING_ALLOWED=NO was set. There is no provisioning profile and no Apple ID.

You can try to sign the .ipa later with Sideloadly or AltStore. Change
BASE_BUNDLE_ID in project.yml away from the placeholder com.example.sleeppause
before you distribute it. HealthKit and the App Group stay inert until the
App ID has those capabilities.

The watch app is not installable this way. Sideloadly and AltStore install the
iOS app only. SleepPauseWatch is embedded for a normal Xcode install and will
not be installed onto an Apple Watch from this unsigned iOS package.
EOF

grep -E "warning:" "$LOGS"/*.log | head -n 400 > "$LOGS/warnings.txt" || true
echo "All required builds succeeded."
