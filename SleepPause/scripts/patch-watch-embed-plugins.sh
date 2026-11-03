#!/usr/bin/env bash
# 仅当 Xcode 安装时报错 “...is a Foundation extension and must be embedded in the parent app
# bundle's PlugIns directory” 时才运行（见 XcodeGen issue #1613）。
set -euo pipefail
cd "$(dirname "$0")/.."
P=SleepPause.xcodeproj/project.pbxproj
sed -i '' -e 's|dstPath = "$(CONTENTS_FOLDER_PATH)/Watch";|dstPath = "";|' -e 's|dstSubfolderSpec = 16;|dstSubfolderSpec = 13;|' "$P"
echo "patched $P"
