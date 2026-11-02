#!/bin/bash
# 在专用 QA 模拟器中构建、安装并启动 LifeOS，截取 DEBUG 预览截图。
# 使用 simctl，可配合 Xcode Device Hub 或其他模拟器查看器；不依赖固定的 Simulator.app 界面。
# 默认保留应用数据；只有显式 RESET_QA_DATA=1 才允许删除已安装的 LifeOS 数据。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-14-Pro-Max"
DEFAULT_QA_DEVICE_NAME="LifeOS QA iPhone 14 Pro Max"
DEVICE_NAME_EXPLICIT=0
if [ "${DEVICE_NAME+x}" = x ]; then
    DEVICE_NAME_EXPLICIT=1
    if [ -z "$DEVICE_NAME" ]; then
        echo "❌ DEVICE_NAME 不能为空；请省略该变量以使用专用 QA 设备。"
        exit 1
    fi
else
    DEVICE_NAME="$DEFAULT_QA_DEVICE_NAME"
fi
case "$DEVICE_NAME" in
    *$'\n'*|*$'\r'*)
        echo "❌ DEVICE_NAME 不能包含换行。"
        exit 1
        ;;
esac

RESET_QA_DATA="${RESET_QA_DATA-0}"
case "$RESET_QA_DATA" in
    0|1) ;;
    *)
        echo "❌ RESET_QA_DATA 只接受 0（保留）或 1（删除 LifeOS 应用数据）。"
        exit 1
        ;;
esac
IS_QA_DEVICE=0
case "$DEVICE_NAME" in
    "LifeOS QA "*) IS_QA_DEVICE=1 ;;
esac
if [ "$RESET_QA_DATA" = 1 ] && [ "$IS_QA_DEVICE" = 0 ] && [ "$DEVICE_NAME_EXPLICIT" != 1 ]; then
    echo "❌ 重置非 QA 设备必须同时显式设置 DEVICE_NAME 和 RESET_QA_DATA=1。"
    exit 1
fi
CREATED_NEW_DEVICE=0
CAPTURE_EMPTY_STATES=0
BUNDLE_ID="com.example.LifeOS"
SHOT_DIR="$ROOT/docs/screenshots"
DERIVED_DATA="$ROOT/.build/DerivedDataSim"

echo "==> DEBUG 截图流程：$DEVICE_NAME"
echo "    默认保留已安装的 LifeOS 数据；后续 -seedPreviewData 可能写入并保留预览记录。"
if [ "$IS_QA_DEVICE" = 0 ]; then
    echo "    ⚠️ 当前显式选择了非专用 QA 设备，建议使用默认的 LifeOS QA 设备。"
fi
if [ "$RESET_QA_DATA" = 1 ]; then
    echo "    ⚠️ 已显式启用 RESET_QA_DATA=1：将删除此设备上已安装的 LifeOS 应用数据。"
fi

echo "==> 检查模拟器运行时"
RUNTIME_ID="$(xcrun simctl list runtimes 2>/dev/null | grep -E '^iOS ' | head -1 | sed -E 's/.*(com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+).*/\1/')" || RUNTIME_ID=""
if [ -z "${RUNTIME_ID:-}" ]; then
    echo "❌ 没有安装 iOS 模拟器运行时。"
    echo "   请打开 Xcode → Settings → Components，下载 iOS Simulator 后再运行本脚本。"
    exit 1
fi
echo "    运行时: $RUNTIME_ID"

echo "==> 准备模拟器: $DEVICE_NAME"
# 精确匹配完整名称，拒绝同名设备，避免 grep 子串匹配到另一台设备后执行重置。
AVAILABLE_DEVICES="$(xcrun simctl list devices available)"
DEVICE_MATCH_COUNT=0
UDID=""
while IFS= read -r device_line; do
    device_line="${device_line#"${device_line%%[![:space:]]*}"}"
    if [[ "$device_line" == "$DEVICE_NAME ("* ]]; then
        candidate_udid="${device_line#"$DEVICE_NAME ("}"
        candidate_udid="${candidate_udid%%)*}"
        if [[ "$candidate_udid" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
            DEVICE_MATCH_COUNT=$((DEVICE_MATCH_COUNT + 1))
            UDID="$candidate_udid"
        fi
    fi
done <<< "$AVAILABLE_DEVICES"
if [ "$DEVICE_MATCH_COUNT" -gt 1 ]; then
    echo "❌ 找到多台名称完全相同的设备：$DEVICE_NAME。"
    echo "   请使用 Device Hub / Xcode 为设备设置唯一名称，再通过 DEVICE_NAME 指定。"
    exit 1
fi
if [ -z "${UDID:-}" ]; then
    UDID="$(xcrun simctl create "$DEVICE_NAME" "$DEVICE_TYPE" "$RUNTIME_ID")"
    CREATED_NEW_DEVICE=1
    CAPTURE_EMPTY_STATES=1
    echo "    已创建: $UDID"
else
    echo "    已存在: $UDID"
fi

echo "==> 构建模拟器版本"
DESTINATION='generic/platform=iOS Simulator' DERIVED_DATA="$DERIVED_DATA" bash Tools/build-ios.sh >/dev/null

echo "==> 启动模拟器"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

echo "==> 安装 / 升级 LifeOS（默认保留现有数据）"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
if [ "$RESET_QA_DATA" = 1 ]; then
    if xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data >/dev/null 2>&1; then
        echo "    正在删除 $DEVICE_NAME 上的 LifeOS 数据（其他应用和设备设置保留）。"
        xcrun simctl uninstall "$UDID" "$BUNDLE_ID"
        CAPTURE_EMPTY_STATES=1
    else
        echo "    未检测到已安装的 LifeOS；未执行卸载。"
        if [ "$CREATED_NEW_DEVICE" = 0 ]; then
            echo "    无法仅凭检测结果确认已有设备的数据为空，因此跳过空状态截图。"
        fi
    fi
fi
xcrun simctl install "$UDID" "$DERIVED_DATA/Build/Products/Debug-iphonesimulator/LifeOS.app"
xcrun simctl status_bar "$UDID" override \
    --time "9:41" \
    --batteryState charged \
    --batteryLevel 100 \
    --wifiBars 3 \
    --cellularBars 4 2>/dev/null || true

mkdir -p "$SHOT_DIR"

# 首次冷启动可能较慢，先预热一次，避免截到启动白屏。
xcrun simctl launch "$UDID" "$BUNDLE_ID" -tab home >/dev/null 2>&1 || true
sleep 8
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true

capture() {
    local name="$1"
    xcrun simctl io "$UDID" screenshot "$SHOT_DIR/$name" >/dev/null 2>&1 || true
    local size
    size=$(stat -f%z "$SHOT_DIR/$name" 2>/dev/null || echo 0)
    if [ "$size" -lt 200000 ]; then
        sleep 4
        xcrun simctl io "$UDID" screenshot "$SHOT_DIR/$name" >/dev/null 2>&1 || true
    fi
    echo "    截图: docs/screenshots/$name"
}

if [ "$CAPTURE_EMPTY_STATES" = 1 ]; then
    echo "==> 空状态截图（新建设备或显式重置成功）"
    xcrun simctl ui "$UDID" appearance light
    xcrun simctl launch "$UDID" "$BUNDLE_ID" -tab home >/dev/null
    sleep 5
    capture "home-empty-light.png"

    xcrun simctl ui "$UDID" appearance dark
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl launch "$UDID" "$BUNDLE_ID" -tab home >/dev/null
    sleep 4
    capture "home-empty-dark.png"
else
    echo "==> 跳过空状态截图：复用设备并保留现有数据。"
    echo "    home-empty-*.png 不会更新；该目录内已有同名截图可能来自以前的运行。"
    echo "    如需重新生成空状态，请使用新的专用 QA 设备，或显式设置 RESET_QA_DATA=1。"
fi

echo "==> 预览数据截图（仅 DEBUG：-seedPreviewData）"
echo "    预览记录会写入设备数据库并保留；已有记录时预览数据注入可能跳过。"
xcrun simctl ui "$UDID" appearance light
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE_ID" -tab home -seedPreviewData >/dev/null
sleep 5
capture "home-light.png"

xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE_ID" -tab home -scrollBottom >/dev/null
sleep 4
capture "home-bottom.png"

xcrun simctl ui "$UDID" appearance dark
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE_ID" -tab home >/dev/null
sleep 4
capture "home-dark.png"

xcrun simctl ui "$UDID" appearance light
for tab in home finance study assistant schedule; do
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl launch "$UDID" "$BUNDLE_ID" -tab "$tab" >/dev/null
    sleep 4
    capture "tab-$tab.png"
done

echo "==> 记账模块截图"
for financeSection in records calendar stats; do
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl launch "$UDID" "$BUNDLE_ID" -tab finance -financeSection "$financeSection" >/dev/null
    sleep 8
    capture "finance-$financeSection.png"
done

xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE_ID" -tab finance -financeSection stats -scrollBottom >/dev/null
sleep 8
capture "finance-stats-bottom.png"

xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE_ID" -tab finance -openTransactionEditor >/dev/null
sleep 12
capture "finance-editor.png"

xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE_ID" -tab finance -openImportPreview >/dev/null
sleep 12
capture "finance-import-preview.png"

xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE_ID" -tab home -openQuickCapture >/dev/null
sleep 14
capture "quick-capture.png"

echo "==> 学习模块截图"
for studySection in timer tasks stats; do
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl launch "$UDID" "$BUNDLE_ID" -tab study -studySection "$studySection" >/dev/null
    sleep 10
    capture "study-$studySection.png"
done

echo "==> 日程模块截图"
for scheduleMode in day week month; do
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl launch "$UDID" "$BUNDLE_ID" -tab schedule -scheduleMode "$scheduleMode" >/dev/null
    sleep 10
    capture "schedule-$scheduleMode.png"
done

xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE_ID" -tab schedule -openScheduleTaskEditor >/dev/null
sleep 12
capture "schedule-editor.png"

echo "✅ 完成：LifeOS 已在 $DEVICE_NAME（$UDID）中运行；本次数据将保留供下次升级验证。"

