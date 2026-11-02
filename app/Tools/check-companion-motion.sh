#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CHECK_DIR="$ROOT/.build/motion-check"
mkdir -p "$CHECK_DIR"
swiftc -module-cache-path "$CHECK_DIR/cache" \
    LifeOS/Core/DesignSystem/CompanionMotion.swift \
    Tools/check-companion-motion.swift -o "$CHECK_DIR/samples"
"$CHECK_DIR/samples" > "$CHECK_DIR/samples.json"
"${PYTHON_BIN:-python3}" Tools/check-companion-motion.py "$CHECK_DIR/samples.json" "${1:-$CHECK_DIR/result.json}"
