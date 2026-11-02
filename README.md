# LifeOS 自动记账与生活管理

LifeOS 是一款以付款截图自动记账为核心的 iPhone 生活管理应用。本仓库包含 SwiftUI 应用源码和 Agent Skills，涵盖付款截图文字识别、账目生成，以及 AI 对话记忆、学习任务和日程管理。

它提炼自 LifeOS 的开发需求，适用于需要管理学习任务、日程等个人数据的应用。Skill 是给编码 Agent 的工作指南；它不会单独连接数据库、赋予 AI 权限，或保证任何模型能正确执行操作。实际能力需要应用提供存储、权限和工具接口。

## 包含什么

- `app/`：LifeOS iOS 应用、桌面小组件、核心逻辑和测试。
- `skills/lifeos-auto-bookkeeping/SKILL.md`：自动记账 Skill 入口和工作流程。
- `skills/lifeos-memory-action/SKILL.md`：AI 记忆和任务操作 Skill。
- `skills/lifeos-memory-action/references/implementation.md`：记忆检索、精确修改与验证的实现要点。

## 运行 iOS 应用

用 Xcode 打开 `app/LifeOS.xcodeproj` 并选择 `LifeOS` 方案。真机运行前，在 Xcode 中选择自己的签名团队，设置唯一的应用标识，并将主应用和小组件的 App Group 配置为自己团队下的同一个标识。AI 连接信息由使用者在应用中自行配置。项目不附带 API 密钥。

在安装好 Xcode 的 Mac 上可运行核心测试：

```sh
cd app/LifeOSCore
swift test
```

## 安装 Skill 到 Codex

克隆仓库后，将需要的 Skill 文件夹复制到 `~/.codex/skills/`，然后重启 Codex。也可使用 Codex 的 skill-installer，从本仓库选择 `skills/lifeos-auto-bookkeeping` 或 `skills/lifeos-memory-action` 路径安装。

安装后可在项目中提出例如：

> 使用 `$lifeos-auto-bookkeeping`，为这个 App 增加付款截图识别与自动记账，同时处理识别不确定和重复提交。

付款截图识别不等同于直接绑定微信或支付宝账户，也不代表每次支付后 iOS 都会自动截屏。实际触发方式和数据访问取决于应用、系统权限和使用者设置。

## 数据和验证

发布副本排除了原设备的对话、计划、账单、凭据、签名身份和构建缓存；测试使用匿名化样例。验证时应优先使用合成数据；连接实际模型服务或修改真实数据时，遵循用户授权和应用的权限设置。

应用中的五种动物头像和应用图标是为本发布版新生成的原创形象，不包含原来的动漫角色素材。素材由 OpenAI 图像生成工具制作；使用者应根据适用地区的法律和服务条款，自行确认再发布或商业使用的条件。

该 Skill 来自实际开发中的设计经验，并不是某个特定 AI 服务的官方插件。安装 Skill 不等于完成 App 集成。
