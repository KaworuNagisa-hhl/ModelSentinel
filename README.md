# ModelSentinel

ModelSentinel 是一款开源的 macOS AI 客户端线路观察工具。它把当前使用的 AI 客户端、配置模型、Provider、线路类型与可信度证据展示在 MacBook 刘海区域，帮助用户发现第三方中转、动态路由和疑似模型降级。

> ModelSentinel 只提供基于本机配置与响应证据的辅助判断，不是对模型身份的密码学证明。

## 当前支持范围

| 客户端 | 类型 | 当前可检测内容 |
| --- | --- | --- |
| Codex | 桌面端 / CLI | 运行状态、配置模型、Provider、Base URL、协议、凭据类型结构、会话响应证据 |
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
4. **响应声明**：本地代理直接读取真实响应中的 `model` 字段并与请求模型比较；它能发现明显换名，但中转仍可能伪造字段。
5. **行为匹配**：通过工具调用、协议和输出行为与可信基线比对，属于概率性判断。

当前版本已经实现本机客户端检测、Codex 会话证据、本地 Responses 代理和用户授权的主动能力探针。Cursor、Windsurf、VS Code Auto 等尚未接入代理的动态路由场景不会被误标为已验证。

详情右上角会分别显示“来源置信度”和“模型验证状态”。例如“来源 98% / 模型未验证”只表示官方线路或配置来源高度可信，不表示实际响应模型已有 98% 的真实性结论。

检测到 Codex 开始处理首个请求后，ModelSentinel 会自动确认是否存在真实响应及响应标识。后续新请求只显示为继续采集，不会覆盖上一轮结果。Codex 当前的本地会话记录不包含服务端独立返回的 `model` 字段，因此被动检测完成后会明确显示“真实响应已确认 / 模型字段未提供”，而不是让用户无限等待；本地代理截获 Responses 对象中的返回模型 ID 后，会显示“响应声明一致”或“响应模型不匹配”。

## 本地响应代理

本地代理适用于配置了自定义 Base URL 的 Codex、CLI 或 OpenAI Responses 兼容客户端。它只监听 `127.0.0.1`，不安装系统证书，也不进行全局 HTTPS 中间人拦截。

1. 从菜单栏进入“代理与鉴别设置…”。
2. 将当前中转站的真实 Base URL 填入“上游 Base URL”，例如 `https://relay.example.com/v1`。
3. 启用代理并点击“应用并重启代理”。
4. 复制客户端 Base URL，例如 `http://127.0.0.1:8765`，将 AI 客户端原来的 Base URL 替换为该地址。
5. 正常使用客户端。ModelSentinel 会实时转发流式响应，并展示请求模型、响应声明、响应 ID 和延迟。

代理不会保存 Authorization、提示词或回答正文。请求头和正文只在内存中经过代理并被转发到用户指定的上游；解析器只提取顶层 `model`、响应 `model`、响应 ID 和耗时。关闭 ModelSentinel 或停用代理后，本地地址将停止服务，因此切换前应保留原上游配置。

如果上游不返回模型字段，或用户不信任该字段，可在设置中手动运行“主动能力探针”。探针会使用当前 Codex 配置额外发起一次独立模型请求，并在该请求中发送三个合成题目；结果只记录通过数量和耗时。行为探针属于概率性风险信号，不是模型身份的密码学证明。

### Token 消耗

- **什么是输入 Token：** 它是模型在一次请求中需要读取的内容所占的计量单位。本项目的主动探针会新建一个独立请求，因此这里所列的是**探针额外产生的用量**，不是把用户之前的正常聊天重新计算一次，也不会读取用户原有对话或项目代码。
- **本地响应代理：0 个额外模型 Token。** 它只转发用户本来就要发送的正常请求并读取响应元数据，不会为了检测再请求一次模型；用户原请求自身的 Token 消耗仍由所用客户端和 Provider 正常计算。
- **主动能力探针：每点击运行一次，就额外执行 1 个 Codex 回合。** 三个合成题目本身约为 100 个输入 Token，但这次独立请求还包含 Codex CLI 的系统指令、工具定义和运行上下文。按当前实现应保守预留约 **10,000–30,000 个额外输入 Token**，以及约 **100–1,000 个额外输出/推理 Token**；不同 Codex 版本、模型、推理档位、Provider 和中转计费方式可能使实际用量更高或更低。
- **它是否会扣用户额度：** 会。使用 API Key 或按 Token 收费的中转站时，这次探针会作为新增请求计入账单；使用 ChatGPT/Codex 订阅登录时，它会占用相应的 Codex 使用额度或频率限制，但不一定显示为单独的按 Token 扣费。具体规则以账号套餐和 Provider 账单为准。
- 主动探针不会定时运行，也不会在后台自动重复。每次都必须由用户在设置页确认；如果按量计费或额度紧张，建议优先使用零额外消耗的本地响应代理。

上述数字是容量预算，不是固定扣费。最终 Token 数量与费用以所使用模型和 Provider 返回的 usage/账单为准。

## 界面行为

- 带刘海的 MacBook：收起时感应区隐藏在实体刘海内，悬浮后从屏幕顶端展开。
- 刘海与左侧常驻标签共同组成悬浮感应区；鼠标离开整个区域后，使用同一套形变动画缩回常驻状态。
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

- 不向项目维护者上传配置、Token、提示词或回复正文；启用代理时只转发到用户指定的上游。
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
