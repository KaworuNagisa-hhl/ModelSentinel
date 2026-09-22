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

ModelSentinel 优先展示当前前台 AI 客户端，其次依次选择正在运行、已配置和已安装的客户端。菜单栏可查看全部检测结果并手动切换。

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

输出位于 `outputs/ModelSentinel-v0.1.0-macOS-arm64.zip`。打包命令会使用 Swift Release 优化，但当前仍是临时签名构建；面向普通用户公开分发前，应使用 Developer ID、Hardened Runtime 和 Apple 公证。

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
