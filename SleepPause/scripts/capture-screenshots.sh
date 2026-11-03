#!/usr/bin/env bash
# Builds SleepPause for the newest iOS 27 iPhone Pro simulator and a watchOS
# simulator, launches with -screenshotMode, and saves real simulator PNGs.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
OUT="$ROOT/docs/screenshots"
LOGS="$ROOT/ci-logs"
DD="$ROOT/build/ScreenshotDerived"
mkdir -p "$OUT" "$LOGS" "$ROOT/build"
rm -f "$OUT"/*.png

{
  echo "xcode-select: $(xcode-select -p)"
  xcodebuild -version
} | tee "$LOGS/screenshots-environment.txt"

echo "=== xcodegen ==="
xcodegen generate | tee "$LOGS/screenshots-xcodegen.log"

python3 - << 'PY' > "$LOGS/screenshot-devices.env"
import json, re, subprocess, sys

def load(args):
    return json.loads(subprocess.check_output(["xcrun", "simctl", *args], text=True))

runtimes = [r for r in load(["list", "runtimes", "-j"]).get("runtimes", []) if r.get("isAvailable")]
devices = load(["list", "devices", "available", "-j"]).get("devices", {})
types = load(["list", "devicetypes", "-j"]).get("devicetypes", [])

def version_tuple(text):
    nums = [int(n) for n in re.findall(r"\d+", text)]
    return tuple(nums[:3] or [0])

def newest(platform):
    found = [r for r in runtimes if r.get("name", "").startswith(platform) or r.get("identifier", "").find(platform) >= 0]
    preferred = [r for r in found if r.get("version", "").split(".")[0] == "27" or "27" in r.get("name", "")]
    pool = preferred or found
    if not pool:
        sys.exit(f"no {platform} simulator runtime")
    pool.sort(key=lambda r: version_tuple(r.get("version") or r.get("name") or ""))
    return pool[-1]

def existing(runtime, pred):
    ident = runtime["identifier"]
    rows = []
    for key, devs in devices.items():
        if ident not in key and runtime.get("name") not in key:
            continue
        for dev in devs:
            if dev.get("isAvailable", True) and pred(dev.get("name", "")):
                rows.append(dev)
    return rows

def iphone_key(name):
    number = max([int(n) for n in re.findall(r"\d+", name)] or [0])
    if re.search(r"Pro Max|Pro-Max", name):
        rank = 1
    elif re.search(r"\bPro\b", name):
        rank = 0
    else:
        rank = 9
    return (rank, -number)

def watch_key(name):
    number = max([int(n) for n in re.findall(r"\d+", name)] or [0])
    if "Ultra" in name:
        rank = 0
    elif "Series" in name:
        rank = 1
    else:
        rank = 2
    return (rank, -number)

ios = newest("iOS")
watch = newest("watchOS")
phones = existing(ios, lambda n: "iPhone" in n and "Pro" in n)
if not phones:
    phones = existing(ios, lambda n: n.startswith("iPhone"))
watches = existing(watch, lambda n: "Watch" in n)
phones.sort(key=lambda d: iphone_key(d["name"]))
watches.sort(key=lambda d: watch_key(d["name"]))

def create(name, runtime, type_pred):
    match = [t for t in types if type_pred(t.get("name", ""))]
    match.sort(key=lambda t: iphone_key(t["name"]) if "iPhone" in t["name"] else watch_key(t["name"]))
    if not match:
        sys.exit(f"no device type for {name}")
    udid = subprocess.check_output(
        ["xcrun", "simctl", "create", name, match[0]["identifier"], runtime["identifier"]], text=True
    ).strip()
    print(f"created {name} {match[0]['name']} {udid}", file=sys.stderr)
    return udid, match[0]["name"]

if phones:
    phone_udid, phone_name = phones[0]["udid"], phones[0]["name"]
else:
    phone_udid, phone_name = create("SleepPause iPhone", ios, lambda n: "iPhone" in n and "Pro" in n)
if watches:
    watch_udid, watch_name = watches[0]["udid"], watches[0]["name"]
else:
    watch_udid, watch_name = create("SleepPause Watch", watch, lambda n: "Watch" in n)

def emit(key, value):
    text = str(value).replace("'", "'\"'\"'")
    print(f"{key}='{text}'")

emit("PHONE_UDID", phone_udid)
emit("PHONE_NAME", phone_name)
emit("PHONE_RUNTIME", ios.get("version") or ios.get("name"))
emit("WATCH_UDID", watch_udid)
emit("WATCH_NAME", watch_name)
emit("WATCH_RUNTIME", watch.get("version") or watch.get("name"))
PY

# shellcheck disable=SC1091
source "$LOGS/screenshot-devices.env"
echo "iPhone: $PHONE_NAME ($PHONE_RUNTIME) $PHONE_UDID"
echo "Watch: $WATCH_NAME ($WATCH_RUNTIME) $WATCH_UDID"

boot() {
  local udid="$1"
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b
}

prepare_language() {
  local udid="$1"
  xcrun simctl spawn "$udid" defaults write NSGlobalDomain AppleLanguages -array zh-Hans || true
  xcrun simctl spawn "$udid" defaults write NSGlobalDomain AppleLocale -string zh_CN || true
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b
}

shot() {
  local udid="$1" bundle="$2" screen="$3" appearance="$4" dest="$5"
  xcrun simctl ui "$udid" appearance "$appearance"
  xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1 || true
  xcrun simctl launch "$udid" "$bundle" \
    -screenshotMode -screenshotScreen "$screen" \
    -AppleLanguages "(zh-Hans)" -AppleLocale "zh_CN"
  sleep 6
  xcrun simctl io "$udid" screenshot "$dest"
  python3 - "$dest" << 'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
if not p.exists() or p.stat().st_size < 20000:
    sys.exit(f"screenshot too small or missing: {p}")
print(f"OK {p.name} {p.stat().st_size} bytes")
PY
}

echo "=== build iOS simulator ==="
xcodebuild \
  -project SleepPause.xcodeproj \
  -scheme SleepPause \
  -destination "platform=iOS Simulator,id=$PHONE_UDID" \
  -configuration Debug \
  -derivedDataPath "$DD" \
  CODE_SIGNING_ALLOWED=YES \
  "CODE_SIGN_IDENTITY=-" \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build | tee "$LOGS/screenshots-ios.log"

PHONE_APP="$(find "$DD/Build/Products" -type d -name 'SleepPause.app' -path '*iphonesimulator*' | head -n 1)"
if [[ -z "$PHONE_APP" ]]; then
  echo "iOS .app not found"
  exit 1
fi

echo "=== build watchOS simulator ==="
xcodebuild \
  -project SleepPause.xcodeproj \
  -scheme SleepPauseWatch \
  -destination "platform=watchOS Simulator,id=$WATCH_UDID" \
  -configuration Debug \
  -derivedDataPath "$DD" \
  CODE_SIGNING_ALLOWED=YES \
  "CODE_SIGN_IDENTITY=-" \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build | tee "$LOGS/screenshots-watch.log"

WATCH_APP="$(find "$DD/Build/Products" -type d -name 'SleepPauseWatch.app' -path '*watchsimulator*' | head -n 1)"
if [[ -z "$WATCH_APP" ]]; then
  echo "watch .app not found"
  exit 1
fi

boot "$PHONE_UDID"
prepare_language "$PHONE_UDID"
xcrun simctl privacy "$PHONE_UDID" grant all com.example.sleeppause || true
xcrun simctl status_bar "$PHONE_UDID" override --time "09:41" --batteryState charged --batteryLevel 100 --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 || true
codesign --force --deep --sign - "$PHONE_APP"
xcrun simctl install "$PHONE_UDID" "$PHONE_APP"

for appearance in light dark; do
  for screen in sleep zone focus weekly onboarding headphones widget; do
    shot "$PHONE_UDID" com.example.sleeppause "$screen" "$appearance" "$OUT/ios-${screen}-${appearance}.png"
  done
done

boot "$WATCH_UDID"
prepare_language "$WATCH_UDID"
codesign --force --deep --sign - "$WATCH_APP"
xcrun simctl install "$WATCH_UDID" "$WATCH_APP"
for appearance in light dark; do
  for screen in idle bedtime; do
    shot "$WATCH_UDID" com.example.sleeppause.watchkitapp "$screen" "$appearance" "$OUT/watch-${screen}-${appearance}.png"
  done
done

xcrun simctl shutdown "$PHONE_UDID" >/dev/null 2>&1 || true
xcrun simctl shutdown "$WATCH_UDID" >/dev/null 2>&1 || true
echo "Screenshots written to $OUT"
ls -la "$OUT"
