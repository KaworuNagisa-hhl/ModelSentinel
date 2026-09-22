# ModelSentinel 隐私说明

版本 1.1，生效日期：2026 年 9 月 22 日

ModelSentinel 是本地优先的开源 macOS 工具。当前版本没有用户账户、广告 SDK、分析 SDK、崩溃上报 SDK或远程遥测服务。

## 本机读取范围

为识别 AI 客户端、配置模型与线路，软件可能只读访问：

- Codex：`~/.codex/config.toml` 和 `~/.codex/auth.json` 的必要配置与字段结构。
- Claude Code：`~/.claude/settings.json`、`~/.claude.json` 和系统托管设置中的模型、Provider、Base URL 与字段结构。
- Claude Desktop：应用是否安装、是否运行，以及本地 MCP 配置是否存在。
- Cursor、Windsurf、VS Code、Zed：应用状态、用户设置中的公开模型或 Base URL 字段，以及扩展目录名称。
- ModelSentinel：`~/Library/Application Support/ModelSentinel/status.json` 中由本地探针写入的状态结果。
- macOS 工作区：正在运行及当前前台 GUI 应用的名称和 Bundle Identifier。
- CLI 进程：PID、父 PID、短进程名和可执行文件路径，用于判断 Codex、Claude Code 等 CLI 是否运行以及来自哪个终端或 IDE。不会读取完整命令参数。

## 凭据保护

软件不会为了检测而展示、记录或上传 API Key、OAuth Token、认证 Cookie、提示词、代码内容或模型回复正文。

对于凭据文件，当前检测器只使用字段是否存在来判断“订阅登录”“官方 API Key”“中转 Key”或“企业身份”等类别。界面不会显示凭据值。

## 数据传输与保存

当前版本不会主动把上述配置、检测结果或使用行为发送给项目维护者或第三方服务器，也不建立远程用户档案。

界面数据只存在于当前进程内存和用户自行创建的本地状态文件中。本地文件的保留、备份与删除由用户和操作系统控制。

被检测的 AI 客户端、中转网关或第三方 Provider 可能有自己的数据处理行为；这些行为不由 ModelSentinel 控制，应以相应服务的隐私政策为准。

## 权限

当前版本不要求通讯录、照片、摄像头、麦克风、位置或完整磁盘访问权限。由于应用尚未启用 App Sandbox，它可以读取当前用户有权访问的上述配置路径；代码公开可审计。

## 后续变更

如果后续增加联网探针、代理、自动更新、崩溃上报或其他数据处理能力，本说明将随版本更新，并优先提供明确的开关和本地处理方案。

隐私问题与安全报告请通过项目 GitHub Issues 提交；涉及敏感信息时不要公开 Token、完整配置或对话内容。
