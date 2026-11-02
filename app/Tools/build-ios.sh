#!/bin/bash
# 仅编译 LifeOS（不签名）。适用于没有设备 / 没有登录 Apple ID 的编译验证。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DESTINATION="${DESTINATION:-generic/platform=iOS}"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/.build/DerivedData}"

mkdir -p "$ROOT/.build/cache/tmp" "$ROOT/.build/cache/clang" "$ROOT/.build/cache/swift" "$ROOT/.build/home/Library/Caches"

# 当前 DeepSeek Harness 沙箱不允许写真实 HOME，把 Xcode / SwiftPM 缓存重定向到项目内。
export CFFIXED_USER_HOME="$ROOT/.build/home"
export TMPDIR="$ROOT/.build/cache/tmp"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/cache/clang"
export SWIFT_MODULE_CACHE_PATH="$ROOT/.build/cache/swift"

exec xcodebuild \
    -project LifeOS.xcodeproj \
    -scheme LifeOS \
    -configuration Debug \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox' \
    build
