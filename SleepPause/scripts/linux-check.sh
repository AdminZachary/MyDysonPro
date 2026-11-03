#!/usr/bin/env bash
# Compiles the platform-independent logic + checks with a plain Swift toolchain (Linux or macOS)
# and parse-checks every Swift file (Apple-only frameworks can't be type-checked off macOS).
set -euo pipefail
cd "$(dirname "$0")/.."
SWIFTC=${SWIFTC:-swiftc}
# On a Mac, swiftc needs the macOS SDK or it cannot load the standard library
# (Xcode 27 reports "unable to load standard library for target …macosx27").
sdk_args=()
if [[ -n "${SWIFT_SDK:-}" ]]; then
  sdk_args+=(-sdk "$SWIFT_SDK")
fi
for f in Shared/*.swift iOS/*.swift iOS/*/*.swift iOS/Zone/*/*.swift Watch/*.swift WatchWidgets/*.swift WidgetShared/*.swift Widgets/*.swift; do "$SWIFTC" "${sdk_args[@]}" -parse "$f"; done
echo "parse OK"
mkdir -p .build-check
cp Tests/DetectorChecks.swift .build-check/main.swift
"$SWIFTC" "${sdk_args[@]}" -O Shared/*.swift iOS/SilentAudio.swift iOS/Core/*.swift \
  iOS/Zone/Core/*.swift WidgetShared/ZoneSnapshot.swift Tests/ZoneCoreChecks.swift Tests/ExtrasChecks.swift Tests/PolishChecks.swift .build-check/main.swift -o .build-check/checks
./.build-check/checks
