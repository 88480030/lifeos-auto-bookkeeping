#!/bin/bash
# 在 Mac 上运行 LifeOSCore 的真实单元测试，不需要 iOS 模拟器。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/LifeOSCore"

mkdir -p "$ROOT/.build/cache/tmp" "$ROOT/.build/cache/clang" "$ROOT/.build/cache/swift"

export TMPDIR="$ROOT/.build/cache/tmp"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/cache/clang"
export SWIFT_MODULE_CACHE_PATH="$ROOT/.build/cache/swift"

exec swift test --disable-sandbox "$@"
