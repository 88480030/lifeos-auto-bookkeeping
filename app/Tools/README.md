# LifeOS 本地验证工具

## 自动记忆缓存

`bash Tools/test-ai-memory.sh` 使用合成对话离线检查同义检索、中文短词、来源定位、索引追加/失效、无提示词自动召回，以及旧 JSON 迁移、无损压缩、重启读取、损坏检测和清空后不回流。不会访问真实对话、调用 API 或读取密钥。

对话原文单份保存在 Application Support 的 `lifeos-ai-memory-v2.bin`，采用版本化 JSON + LZFSE 无损压缩与 SHA-256 完整性校验。搜索索引只缓存词语和消息位置，追加消息增量处理；首次构建与存储读写在后台进行。首次升级保留旧 JSON 为迁移备份，新的文件损坏时不回退到过时内容；用户确认清空对话时一并清空旧备份。此存储不包含照片、视频或文件本体，也不包含 API 密钥。

「和 AI 聊聊 → 右上角菜单 → 自动记忆缓存」可本机搜索原文。每次发送自动提供最多 3 条相关历史及相邻上下文；AI 仍可调用历史工具分页核对。匹配基于词语和常见主题，未命中不能解释成“用户从未说过”，不会凭空生成事实。

从项目根目录运行。构建需要已安装的 Xcode；模拟器截图还需要 iOS Simulator 运行时。脚本通过 `xcrun simctl` 操作设备，可配合 Xcode Device Hub 或其他模拟器查看器使用，不依赖固定的 Simulator.app 窗口。

## 人物姿态回归

`bash Tools/check-companion-motion.sh` 编译应用使用的 `CompanionMotion.swift`，检查连续点击不会引入侧歪或姿态跳变，再以原始 PNG 的虹膜位置核对双角色四状态的眼线。需要 Xcode Swift 编译器、Python 3、NumPy、Pillow；可通过 `PYTHON_BIN=/absolute/path/python3` 指定已有 Python。可选第一个参数为结果 JSON 路径，默认输出到 `.build/motion-check/result.json`。读图分析不修改素材。

这项检查用于检测当前贴图和动作模型的头部侧歪，不替代模拟器中的连接、遮挡、布局或流畅度检查。

## 构建与核心测试

```bash
# 仅编译，不签名，不安装应用
bash Tools/build-ios.sh

# 仅编译模拟器版本
DESTINATION='generic/platform=iOS Simulator' bash Tools/build-ios.sh

# 在 Mac 上运行核心逻辑测试
bash Tools/test-core.sh
```

## 模拟器截图与升级验证

```bash
bash Tools/run-simulator.sh
```

默认设备为 **LifeOS QA iPhone 14 Pro Max**。设备不存在时创建；已存在时复用。安装新的 DEBUG 构建时保留已安装 LifeOS 的数据库与设置，不自动卸载应用或抹掉模拟器。请保留专用 QA 设备，用它检查升级前后的记录。

这是截图脚本，会启动多个页面、切换浅色和深色、覆盖 `docs/screenshots/` 中对应的截图，并在后半段显式使用 DEBUG 参数 `-seedPreviewData`。当前预览数据注入器仅在交易、日程和学习记录都为空时写入示例；数据会留在设备中，下一次运行仍可见。已有数据时注入可能跳过，带数据截图也可能反映现有记录。

需要一台独立的空设备时，指定一个新的 QA 名称：

```bash
DEVICE_NAME='LifeOS QA Fresh iPhone 14 Pro Max' bash Tools/run-simulator.sh
```

设备按**完整名称精确匹配**。同名设备超过一台时脚本停止，请先在 Device Hub / Xcode 中给设备设置唯一名称，避免选错目标。

### 显式清除 LifeOS 数据

以下命令会卸载目标设备上的 LifeOS，再重新安装。该应用数据库和设置会被删除，其他应用及模拟器设置保留。

```bash
# 清除默认专用 QA 设备上的 LifeOS 数据
RESET_QA_DATA=1 bash Tools/run-simulator.sh

# 清除明确指定的另一台 QA 设备上的 LifeOS 数据
DEVICE_NAME='LifeOS QA Fresh iPhone 14 Pro Max' RESET_QA_DATA=1 bash Tools/run-simulator.sh
```

`RESET_QA_DATA` 只接受 `0`（默认保留）或 `1`（显式清除）。非 QA 设备只有在同时显式提供完整 `DEVICE_NAME` 和 `RESET_QA_DATA=1` 时才允许清除；脚本会打印目标名称与删除提示。不要对保有个人记录的设备使用重置选项。

### 空状态截图的含义

只有本次新建设备，或本次显式重置并成功卸载了已安装的 LifeOS，才重新生成 `home-empty-light.png` 与 `home-empty-dark.png`。如果复用设备并保留数据，脚本跳过这两张截图，避免把已有记录的页面命名为空状态。

若在已有设备上无法检测到已安装的 LifeOS，脚本不会把检测失败当作数据库为空的证明，也不会据此生成空状态截图。跳过时截图目录里的旧 `home-empty-*.png` 会保留，**不代表本次运行结果**。需要新的空状态证据时，优先使用一个新的专用 QA 设备名称。
