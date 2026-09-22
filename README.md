# ModelSentinel

ModelSentinel 是一款开源的 macOS AI 客户端线路观察工具。它把当前使用的 AI 客户端、配置模型、Provider、线路类型与可信度证据展示在 MacBook 刘海区域，帮助用户发现第三方中转、动态路由和疑似模型降级。

> ModelSentinel 只提供基于本机配置与响应证据的辅助判断，不是对模型身份的密码学证明。

## 当前支持范围

| 客户端 | 类型 | 当前可检测内容 |
| --- | --- | --- |
| Codex | 桌面端 / CLI | 运行状态、配置模型、Provider、Base URL、协议、凭据类型结构 |
| ChatGPT | 桌面端 | 安装与运行状态、官方订阅线路；具体模型等待响应证据 |
| Claude Desktop | 桌面端 | 安装与运行状态、官方服务、MCP 配置是否存在 |
| Claude Code | CLI | 模型、`ANTHROPIC_BASE_URL`、Bedrock、Vertex、凭据类型结构 |
| Cursor | IDE | 安装、运行、用户配置和 AI 扩展；实际上游等待响应证据 |
| Windsurf | IDE | 安装、运行、用户配置和 AI 扩展；实际上游等待响应证据 |
| Visual Studio Code | IDE | 运行状态、模型设置、Copilot / Claude / Codex / Continue / Cline / Roo Code 等扩展 |
| Zed | IDE | 安装、运行、Provider 配置与自定义 Base URL 线索 |
| Gemini CLI / Aider / OpenCode / Amp / Qwen Code | CLI | 安装、CLI 进程、宿主终端或 IDE、配置模型与 Base URL 线索 |

ModelSentinel 优先展示当前前台 AI 客户端，其次依次选择正在运行、已配置和已安装的客户端。菜单栏可查看全部检测结果并手动切换。

CLI 进程每 2 秒在本机刷新一次。进程扫描只读取 PID、父 PID、短进程名和可执行文件路径，不读取完整命令参数，因此不会把命令行中的提示词或密钥收集进来。能够沿父进程识别 Terminal、iTerm、Warp、VS Code、Cursor、Windsurf、Zed 和部分 JetBrains 系 IDE；无法证明关联关系时会显示为后台 CLI，而不会假定其属于当前窗口。

对于 Codex Desktop，ModelSentinel 还会从最近活动的本机会话 JSONL 尾部提取模型 ID、推理档位、上下文窗口以及任务开始/完成状态，用来区分“仅安装”“正在运行”和“当前正在处理请求”。消息正文、提示词、回答内容和工具参数不会被保存或展示。

## 安装

### 一键安装脚本

默认安装到 `~/Applications/ModelSentinel.app`，不需要 `sudo`。脚本会下载 Release 和 `SHA256SUMS.txt`，校验通过后才安装；已有版本会先备份。

```bash
curl -fsSL https://raw.githubusercontent.com/KaworuNagisa-hhl/ModelSentinel/main/install.sh | bash
```

更稳妥的做法是先下载并检查脚本：

```bash
curl -fsSLO https://raw.githubusercontent.com/KaworuNagisa-hhl/ModelSentinel/main/install.sh
less install.sh
bash install.sh
```

自定义安装目录或版本：

```bash
MODEL_SENTINEL_INSTALL_DIR="$HOME/Applications" \
MODEL_SENTINEL_VERSION="0.2.0" \
bash install.sh
```

当前预览包尚未使用 Developer ID 签名和 Apple 公证。如果首次启动被 Gatekeeper 拦截，请进入“系统设置 → 隐私与安全性”，确认应用来源后选择“仍要打开”。安装脚本不会自动删除隔离属性或绕过 macOS 安全检查。

### 手动安装

1. 从 [GitHub Releases](https://github.com/KaworuNagisa-hhl/ModelSentinel/releases) 下载 arm64 ZIP 和 `SHA256SUMS.txt`。
2. 运行 `shasum -a 256 -c SHA256SUMS.txt` 校验安装包。
3. 解压并把 `ModelSentinel.app` 移到 `~/Applications` 或 `/Applications`。
4. 启动后，ModelSentinel 常驻菜单栏；带刘海的 MacBook 可将鼠标移动到刘海区域展开。

## 证据分级

为了避免把“配置值”误报成“真实模型”，界面明确区分：

1. **已安装**：只证明本机存在应用或命令。
2. **正在运行**：证明 GUI 客户端当前存在进程。
3. **配置已识别**：读取到模型、Provider 或 Base URL 等本机配置。
4. **响应已验证**：只有捕获到真实请求或响应元数据后，才展示响应模型与实时延迟。
5. **行为匹配**：通过工具调用、协议和输出行为与可信基线比对，属于概率性判断。

当前版本已经实现前三层和本地状态文件入口；响应遥测与行为探针仍在开发中。因此 Cursor、Windsurf、VS Code Auto 等动态路由场景不会被误标为已验证。

## 界面行为

- 带刘海的 MacBook：收起时感应区隐藏在实体刘海内，悬浮后从屏幕顶端展开。
- 收起时在实体刘海左侧常驻发光状态灯：绿色为已验证正常，黄色为疑似或等待验证，红色为明确异常或离线。
- 状态灯在收起和展开时保持同一位置基准，并随黑色表面以 0.38 秒连续形变动画移动到详情头部。
- 黑色毛玻璃与实体刘海无缝衔接，顶部直角、底部圆角。
- 无刘海显示器自动退化为顶部紧凑状态岛。
- 菜单栏可重新扫描客户端、手动切换检测对象和监听本地状态文件。

## 构建

要求：

- macOS 14 或更高版本
- Swift 6 工具链
- Apple Silicon Mac（当前打包脚本生成 arm64 应用）

```bash
swift build
./script/build_and_run.sh
```

生成 Release ZIP：

```bash
./script/build_and_run.sh --package
```

输出位于 `outputs/ModelSentinel-v0.2.0-macOS-arm64.zip`。打包命令会使用 Swift Release 优化，但当前仍是临时签名构建；面向普通用户公开分发前，应使用 Developer ID、Hardened Runtime 和 Apple 公证。

## 本地状态文件

外部代理或客户端插件可以把真实响应证据写入：

```text
~/Library/Application Support/ModelSentinel/status.json
```

格式参考 [`status.example.json`](status.example.json)。模型身份字段缺失时，ModelSentinel 会继续显示“等待响应”，不会用配置模型冒充响应模型。

为避免旧数据制造“线路可信”的假象，状态文件修改时间超过 2 分钟，或内部 `updatedAt` 超过 5 分钟时会被忽略。持续运行的探针应在产生新证据时原子更新文件和时间戳。

## 隐私

ModelSentinel 采用本地优先设计：

- 不上传配置、Token、提示词或回复正文。
- 只读取识别线路所需的配置字段和扩展目录名称。
- 不展示 API Key、OAuth Token 或其他凭据内容。
- 当前版本不含广告、分析 SDK、崩溃上报或远程遥测。

详见 [`PRIVACY.md`](PRIVACY.md)。

## 贡献新的客户端适配器

客户端扫描集中在 `RouteOriginDetector`，展示模型位于 `AIClient`、`RouteOrigin` 和 `RouteSnapshot`。新增适配器时请遵守：

- 不读取或记录密钥值，只判断必要字段是否存在。
- 将安装、运行、配置、响应和行为证据分开。
- 未捕获真实响应时，不得声称已确认实际模型。
- Provider 名称、端口或域名只能作为证据，不能单独作为绝对结论。

欢迎提交适配器、测试样例和不同客户端的匿名配置结构。

## 许可

ModelSentinel 使用 [MIT License](LICENSE) 开源。

Codex、ChatGPT、Claude、Cursor、Windsurf、Visual Studio Code、GitHub Copilot、Zed 等名称及商标归各自权利人所有。ModelSentinel 与这些产品的权利人不存在隶属或官方合作关系，除非另有明确说明。
