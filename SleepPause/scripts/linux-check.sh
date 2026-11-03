#!/usr/bin/env bash
# Compiles the platform-independent logic + checks with a plain Swift toolchain (Linux or macOS)
# and parse-checks every Swift file (Apple-only frameworks can't be type-checked off macOS).
set -euo pipefail
cd "$(dirname "$0")/.."
SWIFTC=${SWIFTC:-swiftc}
for f in Shared/*.swift iOS/*.swift iOS/*/*.swift iOS/Zone/*/*.swift Watch/*.swift WatchWidgets/*.swift WidgetShared/*.swift Widgets/*.swift; do "$SWIFTC" -parse "$f"; done
echo "parse OK"
mkdir -p .build-check
cp Tests/DetectorChecks.swift .build-check/main.swift
"$SWIFTC" -O Shared/*.swift iOS/SilentAudio.swift iOS/Core/*.swift \
  iOS/Zone/Core/*.swift WidgetShared/ZoneSnapshot.swift Tests/ZoneCoreChecks.swift Tests/ExtrasChecks.swift Tests/PolishChecks.swift .build-check/main.swift -o .build-check/checks
./.build-check/checks
