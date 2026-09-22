import Foundation

actor RouteOriginDetector {
    static let shared = RouteOriginDetector()

    private let fileManager: FileManager
    private let homeDirectory: URL

    init(fileManager: FileManager = .default, homeDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
    }

    func detectEnvironment(runtime: AIClientRuntimeContext) -> ClientEnvironmentDetection {
        let probes = [
            detectCodex(runtime: runtime),
            detectChatGPT(runtime: runtime),
            detectClaudeDesktop(runtime: runtime),
            detectClaudeCode(),
            detectCursor(runtime: runtime),
            detectWindsurf(runtime: runtime),
            detectVisualStudioCode(runtime: runtime),
            detectZed(runtime: runtime)
        ].compactMap { $0 }
        .sorted { score($0.client) > score($1.client) }

        return ClientEnvironmentDetection(matches: probes, active: probes.first)
    }

    func detectCodexRoute() -> RouteOrigin {
        codexRouteAndModel().origin
    }

    func detectCodexModelDetails() -> ModelIdentityDetails {
        codexRouteAndModel().model
    }

    private func detectCodex(runtime: AIClientRuntimeContext) -> ClientRouteDetection? {
        let bundleFragments = ["openai.codex", ".codex"]
        let nameFragments = ["Codex"]
        let configURL = codexHomeURL().appendingPathComponent("config.toml")
        let hasConfiguration = fileManager.fileExists(atPath: configURL.path)
        let isInstalled = hasInstalledApplication(named: "Codex.app") ||
            executableExists(at: ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"])
        let isRunning = runtime.isRunning(bundleFragments: bundleFragments, nameFragments: nameFragments)
        guard isInstalled || isRunning || hasConfiguration else { return nil }

        var evidence = clientEvidence(
            isInstalled: isInstalled,
            isRunning: isRunning,
            hasConfiguration: hasConfiguration,
            configurationName: "~/.codex/config.toml"
        )
        if fileManager.fileExists(atPath: codexHomeURL().appendingPathComponent("auth.json").path) {
            evidence.append("发现 Codex 凭据结构（不读取 Token 内容）")
        }

        let resolved = codexRouteAndModel()
        return ClientRouteDetection(
            client: AIClientDetection(
                id: "codex",
                kind: .codex,
                displayName: "Codex",
                surface: .desktopApp,
                isInstalled: isInstalled,
                isRunning: isRunning,
                isFrontmost: runtime.isFrontmost(bundleFragments: bundleFragments, nameFragments: nameFragments),
                hasConfiguration: hasConfiguration,
                integrations: [],
                evidence: evidence
            ),
            origin: resolved.origin,
            modelDetails: resolved.model
        )
    }

    private func detectChatGPT(runtime: AIClientRuntimeContext) -> ClientRouteDetection? {
        let bundleFragments = ["openai.chat", "chatgpt"]
        let nameFragments = ["ChatGPT"]
        let isInstalled = hasInstalledApplication(named: "ChatGPT.app")
        let isRunning = runtime.isRunning(bundleFragments: bundleFragments, nameFragments: nameFragments)
        guard isInstalled || isRunning else { return nil }

        return managedClientProbe(
            id: "chatgpt",
            kind: .chatGPT,
            displayName: "ChatGPT",
            surface: .desktopApp,
            isInstalled: isInstalled,
            isRunning: isRunning,
            isFrontmost: runtime.isFrontmost(bundleFragments: bundleFragments, nameFragments: nameFragments),
            hasConfiguration: false,
            integrations: [],
            origin: RouteOrigin(
                kind: .officialSubscription,
                credentialKind: .chatGPTSubscription,
                displayName: "OpenAI · ChatGPT 官方服务",
                host: "chatgpt.com",
                confidence: 0.90,
                evidence: ["检测到官方 ChatGPT 客户端", "具体响应模型需从会话证据确认"]
            ),
            providerID: "openai"
        )
    }

    private func detectClaudeDesktop(runtime: AIClientRuntimeContext) -> ClientRouteDetection? {
        let bundleFragments = ["anthropic.claude", "claudefordesktop"]
        let nameFragments = ["Claude"]
        let configURL = applicationSupportURL("Claude/claude_desktop_config.json")
        let hasConfiguration = fileManager.fileExists(atPath: configURL.path)
        let isInstalled = hasInstalledApplication(named: "Claude.app")
        let isRunning = runtime.isRunning(bundleFragments: bundleFragments, nameFragments: nameFragments)
        guard isInstalled || isRunning || hasConfiguration else { return nil }

        return managedClientProbe(
            id: "claude-desktop",
            kind: .claudeDesktop,
            displayName: "Claude Desktop",
            surface: .desktopApp,
            isInstalled: isInstalled,
            isRunning: isRunning,
            isFrontmost: runtime.isFrontmost(bundleFragments: bundleFragments, nameFragments: nameFragments),
            hasConfiguration: hasConfiguration,
            integrations: hasConfiguration ? ["MCP"] : [],
            origin: RouteOrigin(
                kind: .officialSubscription,
                credentialKind: .claudeSubscription,
                displayName: "Anthropic · Claude 官方服务",
                host: "claude.ai",
                confidence: 0.90,
                evidence: ["检测到官方 Claude Desktop", "MCP 配置不等同于模型线路证据"]
            ),
            providerID: "anthropic"
        )
    }

    private func detectClaudeCode() -> ClientRouteDetection? {
        let userSettingsURL = homeDirectory.appendingPathComponent(".claude/settings.json")
        let userStateURL = homeDirectory.appendingPathComponent(".claude.json")
        let managedSettingsURL = URL(fileURLWithPath: "/Library/Application Support/ClaudeCode/managed-settings.json")
        let settingsURLs = [managedSettingsURL, userSettingsURL]
        let hasConfiguration = settingsURLs.contains { fileManager.fileExists(atPath: $0.path) } ||
            fileManager.fileExists(atPath: userStateURL.path)
        let isInstalled = executableExists(at: [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            homeDirectory.appendingPathComponent(".local/bin/claude").path
        ])
        guard isInstalled || hasConfiguration else { return nil }

        var mergedEnvironment: [String: String] = [:]
        var selectedModel: String?
        for settingsURL in settingsURLs {
            guard let settings = loadJSONDictionary(at: settingsURL) else { continue }
            if let model = settings["model"] as? String, !model.isEmpty { selectedModel = model }
            if let environment = settings["env"] as? [String: Any] {
                for (key, value) in environment {
                    if let value = value as? String { mergedEnvironment[key] = value }
                }
            }
        }

        let useBedrock = isTruthy(mergedEnvironment["CLAUDE_CODE_USE_BEDROCK"])
        let useVertex = isTruthy(mergedEnvironment["CLAUDE_CODE_USE_VERTEX"])
        let baseURL = mergedEnvironment["ANTHROPIC_BASE_URL"]
            ?? mergedEnvironment["ANTHROPIC_BEDROCK_BASE_URL"]
            ?? mergedEnvironment["ANTHROPIC_VERTEX_BASE_URL"]
        selectedModel = mergedEnvironment["ANTHROPIC_MODEL"] ?? selectedModel

        let origin: RouteOrigin
        let providerID: String
        if useBedrock {
            providerID = "amazon-bedrock"
            origin = RouteOrigin(
                kind: .enterpriseCloud,
                credentialKind: .enterpriseIdentity,
                displayName: "Amazon Bedrock",
                host: host(from: baseURL),
                confidence: 0.96,
                evidence: ["Claude Code 配置启用 CLAUDE_CODE_USE_BEDROCK"]
            )
        } else if useVertex {
            providerID = "google-vertex"
            origin = RouteOrigin(
                kind: .enterpriseCloud,
                credentialKind: .enterpriseIdentity,
                displayName: "Google Vertex AI",
                host: host(from: baseURL),
                confidence: 0.96,
                evidence: ["Claude Code 配置启用 CLAUDE_CODE_USE_VERTEX"]
            )
        } else if let baseURL, !baseURL.isEmpty {
            providerID = host(from: baseURL) ?? "custom-anthropic"
            origin = classifyEndpoint(baseURL, declaredName: "Claude Code", credentialKind: .relayKey)
        } else {
            providerID = "anthropic"
            let credential = claudeCredentialKind(userStateURL: userStateURL, environment: mergedEnvironment)
            origin = RouteOrigin(
                kind: credential == .claudeSubscription ? .officialSubscription : .officialAPI,
                credentialKind: credential,
                displayName: credential == .claudeSubscription
                    ? "Anthropic · Claude 订阅"
                    : "Anthropic · 官方 API",
                host: "api.anthropic.com",
                confidence: credential == .unknown ? 0.62 : 0.92,
                evidence: ["未配置自定义 ANTHROPIC_BASE_URL", "凭据内容未被读取"]
            )
        }

        return ClientRouteDetection(
            client: AIClientDetection(
                id: "claude-code",
                kind: .claudeCode,
                displayName: "Claude Code",
                surface: .commandLine,
                isInstalled: isInstalled,
                isRunning: false,
                isFrontmost: false,
                hasConfiguration: hasConfiguration,
                integrations: [],
                evidence: clientEvidence(
                    isInstalled: isInstalled,
                    isRunning: false,
                    hasConfiguration: hasConfiguration,
                    configurationName: "~/.claude/settings.json"
                )
            ),
            origin: origin,
            modelDetails: ModelIdentityDetails(
                requestedModelID: selectedModel,
                responseModelID: nil,
                behavioralMatch: nil,
                reasoningEffort: nil,
                wireAPI: "anthropic-messages",
                providerID: providerID,
                contextWindowTokens: nil
            )
        )
    }

    private func detectCursor(runtime: AIClientRuntimeContext) -> ClientRouteDetection? {
        detectAIIDE(
            runtime: runtime,
            id: "cursor",
            kind: .cursor,
            displayName: "Cursor",
            appName: "Cursor.app",
            bundleFragments: ["todesktop", "cursor"],
            nameFragments: ["Cursor"],
            settingsRelativePath: "Cursor/User/settings.json",
            extensionDirectory: homeDirectory.appendingPathComponent(".cursor/extensions"),
            credentialKind: .vendorAccount
        )
    }

    private func detectWindsurf(runtime: AIClientRuntimeContext) -> ClientRouteDetection? {
        detectAIIDE(
            runtime: runtime,
            id: "windsurf",
            kind: .windsurf,
            displayName: "Windsurf",
            appName: "Windsurf.app",
            bundleFragments: ["exafunction.windsurf", "windsurf"],
            nameFragments: ["Windsurf"],
            settingsRelativePath: "Windsurf/User/settings.json",
            extensionDirectory: homeDirectory.appendingPathComponent(".windsurf/extensions"),
            credentialKind: .vendorAccount
        )
    }

    private func detectVisualStudioCode(runtime: AIClientRuntimeContext) -> ClientRouteDetection? {
        let bundleFragments = ["com.microsoft.vscode", "visual-studio-code"]
        let nameFragments = ["Visual Studio Code"]
        let settingsURL = applicationSupportURL("Code/User/settings.json")
        let extensionDirectories = [
            homeDirectory.appendingPathComponent(".vscode/extensions"),
            homeDirectory.appendingPathComponent(".vscode-insiders/extensions")
        ]
        let integrations = detectedAIIntegrations(in: extensionDirectories)
        let hasConfiguration = fileManager.fileExists(atPath: settingsURL.path) || !integrations.isEmpty
        let isInstalled = hasInstalledApplication(named: "Visual Studio Code.app")
        let isRunning = runtime.isRunning(bundleFragments: bundleFragments, nameFragments: nameFragments)
        guard isInstalled || isRunning || hasConfiguration else { return nil }

        let settingsText = try? String(contentsOf: settingsURL, encoding: .utf8)
        let requestedModel = settingsText.flatMap {
            jsonLikeStringValue(for: "chat.defaultModel", in: $0)
                ?? jsonLikeStringValue(for: "inlineChat.defaultModel", in: $0)
        }
        let hasCopilot = integrations.contains("GitHub Copilot")

        return ClientRouteDetection(
            client: AIClientDetection(
                id: "vscode",
                kind: .visualStudioCode,
                displayName: "Visual Studio Code",
                surface: .ide,
                isInstalled: isInstalled,
                isRunning: isRunning,
                isFrontmost: runtime.isFrontmost(bundleFragments: bundleFragments, nameFragments: nameFragments),
                hasConfiguration: hasConfiguration,
                integrations: integrations,
                evidence: clientEvidence(
                    isInstalled: isInstalled,
                    isRunning: isRunning,
                    hasConfiguration: hasConfiguration,
                    configurationName: "VS Code 用户设置 / 扩展"
                )
            ),
            origin: RouteOrigin(
                kind: .managedService,
                credentialKind: hasCopilot ? .copilotSubscription : .unknown,
                displayName: hasCopilot
                    ? "VS Code · Copilot / 可切换 Provider"
                    : "VS Code · Provider 待会话确认",
                host: nil,
                confidence: requestedModel == nil ? 0.48 : 0.66,
                evidence: ["VS Code 可在不同会话中切换模型和 Provider", "Auto 模式可能按请求动态路由"] +
                    integrations.map { "已安装 AI 集成：\($0)" }
            ),
            modelDetails: ModelIdentityDetails(
                requestedModelID: requestedModel,
                responseModelID: nil,
                behavioralMatch: nil,
                reasoningEffort: nil,
                wireAPI: nil,
                providerID: hasCopilot ? "github-copilot" : nil,
                contextWindowTokens: nil
            )
        )
    }

    private func detectZed(runtime: AIClientRuntimeContext) -> ClientRouteDetection? {
        let bundleFragments = ["dev.zed.zed", ".zed"]
        let nameFragments = ["Zed"]
        let settingsURL = applicationSupportURL("Zed/settings.json")
        let hasConfiguration = fileManager.fileExists(atPath: settingsURL.path)
        let isInstalled = hasInstalledApplication(named: "Zed.app")
        let isRunning = runtime.isRunning(bundleFragments: bundleFragments, nameFragments: nameFragments)
        guard isInstalled || isRunning || hasConfiguration else { return nil }

        let settingsText = try? String(contentsOf: settingsURL, encoding: .utf8)
        let baseURL = settingsText.flatMap {
            jsonLikeStringValue(for: "api_url", in: $0)
                ?? jsonLikeStringValue(for: "base_url", in: $0)
        }
        let origin = baseURL.map {
            classifyEndpoint($0, declaredName: "Zed", credentialKind: .providerAPIKey)
        } ?? RouteOrigin(
            kind: .managedService,
            credentialKind: .vendorAccount,
            displayName: "Zed · Provider 待会话确认",
            host: nil,
            confidence: 0.48,
            evidence: ["Zed 支持多个模型 Provider；未发现明确 Base URL"]
        )

        return ClientRouteDetection(
            client: AIClientDetection(
                id: "zed",
                kind: .zed,
                displayName: "Zed",
                surface: .ide,
                isInstalled: isInstalled,
                isRunning: isRunning,
                isFrontmost: runtime.isFrontmost(bundleFragments: bundleFragments, nameFragments: nameFragments),
                hasConfiguration: hasConfiguration,
                integrations: [],
                evidence: clientEvidence(
                    isInstalled: isInstalled,
                    isRunning: isRunning,
                    hasConfiguration: hasConfiguration,
                    configurationName: "Zed settings.json"
                )
            ),
            origin: origin,
            modelDetails: ModelIdentityDetails(
                requestedModelID: nil,
                responseModelID: nil,
                behavioralMatch: nil,
                reasoningEffort: nil,
                wireAPI: nil,
                providerID: nil,
                contextWindowTokens: nil
            )
        )
    }

    private func detectAIIDE(
        runtime: AIClientRuntimeContext,
        id: String,
        kind: AIClientKind,
        displayName: String,
        appName: String,
        bundleFragments: [String],
        nameFragments: [String],
        settingsRelativePath: String,
        extensionDirectory: URL,
        credentialKind: RouteCredentialKind
    ) -> ClientRouteDetection? {
        let settingsURL = applicationSupportURL(settingsRelativePath)
        let integrations = detectedAIIntegrations(in: [extensionDirectory])
        let hasConfiguration = fileManager.fileExists(atPath: settingsURL.path) || !integrations.isEmpty
        let isInstalled = hasInstalledApplication(named: appName)
        let isRunning = runtime.isRunning(bundleFragments: bundleFragments, nameFragments: nameFragments)
        guard isInstalled || isRunning || hasConfiguration else { return nil }

        return managedClientProbe(
            id: id,
            kind: kind,
            displayName: displayName,
            surface: .ide,
            isInstalled: isInstalled,
            isRunning: isRunning,
            isFrontmost: runtime.isFrontmost(bundleFragments: bundleFragments, nameFragments: nameFragments),
            hasConfiguration: hasConfiguration,
            integrations: integrations,
            origin: RouteOrigin(
                kind: .managedService,
                credentialKind: credentialKind,
                displayName: "\(displayName) 托管线路 · 上游待确认",
                host: nil,
                confidence: 0.56,
                evidence: ["客户端可能按功能或请求动态选择上游模型", "需要响应遥测才能确认实际模型"]
            ),
            providerID: id
        )
    }

    private func managedClientProbe(
        id: String,
        kind: AIClientKind,
        displayName: String,
        surface: AIClientSurface,
        isInstalled: Bool,
        isRunning: Bool,
        isFrontmost: Bool,
        hasConfiguration: Bool,
        integrations: [String],
        origin: RouteOrigin,
        providerID: String
    ) -> ClientRouteDetection {
        ClientRouteDetection(
            client: AIClientDetection(
                id: id,
                kind: kind,
                displayName: displayName,
                surface: surface,
                isInstalled: isInstalled,
                isRunning: isRunning,
                isFrontmost: isFrontmost,
                hasConfiguration: hasConfiguration,
                integrations: integrations,
                evidence: clientEvidence(
                    isInstalled: isInstalled,
                    isRunning: isRunning,
                    hasConfiguration: hasConfiguration,
                    configurationName: integrations.isEmpty ? "客户端配置" : integrations.joined(separator: "、")
                )
            ),
            origin: origin,
            modelDetails: ModelIdentityDetails(
                requestedModelID: nil,
                responseModelID: nil,
                behavioralMatch: nil,
                reasoningEffort: nil,
                wireAPI: nil,
                providerID: providerID,
                contextWindowTokens: nil
            )
        )
    }

    private func codexRouteAndModel() -> (origin: RouteOrigin, model: ModelIdentityDetails) {
        let codexHome = codexHomeURL()
        let config = scanCodexConfig(at: codexHome.appendingPathComponent("config.toml"))
        let providerID = config.modelProvider ?? "openai"
        let provider = config.providers[providerID]
        let localCredential = codexCredentialKind(at: codexHome.appendingPathComponent("auth.json"))

        let origin: RouteOrigin
        if providerID == "amazon-bedrock" {
            origin = RouteOrigin(
                kind: .enterpriseCloud,
                credentialKind: .enterpriseIdentity,
                displayName: "Amazon Bedrock",
                host: nil,
                confidence: 0.98,
                evidence: ["Codex 内置 Provider: amazon-bedrock"]
            )
        } else if let baseURL = provider?.baseURL ?? config.openAIBaseURL, !baseURL.isEmpty {
            let endpointCredential: RouteCredentialKind
            if provider == nil || provider?.requiresOpenAIAuth == true {
                endpointCredential = localCredential
            } else if provider?.usesEnvironmentKey == true {
                endpointCredential = .relayKey
            } else {
                endpointCredential = .noAuthentication
            }
            origin = classifyEndpoint(
                baseURL,
                declaredName: provider?.name ?? providerID,
                credentialKind: endpointCredential
            )
        } else if providerID != "openai" {
            origin = RouteOrigin(
                kind: .unknown,
                credentialKind: provider?.usesEnvironmentKey == true ? .relayKey : .unknown,
                displayName: "自定义 Provider · 来源待确认",
                host: nil,
                confidence: 0.35,
                evidence: ["Provider: \(provider?.name ?? providerID)", "未发现可分类的 Base URL"]
            )
        } else {
            origin = openAIDefaultOrigin(credential: localCredential)
        }

        return (
            origin,
            ModelIdentityDetails(
                requestedModelID: config.model,
                responseModelID: nil,
                behavioralMatch: nil,
                reasoningEffort: config.modelReasoningEffort,
                wireAPI: provider?.wireAPI ?? (providerID == "openai" ? "responses" : nil),
                providerID: providerID,
                contextWindowTokens: nil
            )
        )
    }

    private func openAIDefaultOrigin(credential: RouteCredentialKind) -> RouteOrigin {
        switch credential {
        case .chatGPTSubscription:
            RouteOrigin(
                kind: .officialSubscription,
                credentialKind: .chatGPTSubscription,
                displayName: "OpenAI · ChatGPT 个人订阅",
                host: "chatgpt.com",
                confidence: 0.98,
                evidence: ["Codex 内置 OpenAI Provider", "本机凭据类型为 ChatGPT OAuth"]
            )
        case .officialAPIKey:
            RouteOrigin(
                kind: .officialAPI,
                credentialKind: .officialAPIKey,
                displayName: "OpenAI · 官方 API",
                host: "api.openai.com",
                confidence: 0.98,
                evidence: ["Codex 内置 OpenAI Provider", "本机凭据类型为 API Key"]
            )
        default:
            RouteOrigin(
                kind: .unknown,
                credentialKind: .unknown,
                displayName: "OpenAI · 登录类型待确认",
                host: nil,
                confidence: 0.58,
                evidence: ["Codex 内置 OpenAI Provider", "凭据可能位于 macOS 钥匙串"]
            )
        }
    }

    private func classifyEndpoint(
        _ rawBaseURL: String,
        declaredName: String,
        credentialKind: RouteCredentialKind
    ) -> RouteOrigin {
        let normalized = rawBaseURL.contains("://") ? rawBaseURL : "https://\(rawBaseURL)"
        guard let components = URLComponents(string: normalized),
              let host = components.host?.lowercased() else {
            return RouteOrigin(
                kind: .unknown,
                credentialKind: credentialKind,
                displayName: "自定义线路 · 地址无效",
                host: nil,
                confidence: 0.25,
                evidence: ["Provider: \(declaredName)"]
            )
        }

        let port = components.port
        let lowerName = declaredName.lowercased()
        let authEvidence = credentialEvidence(for: credentialKind)

        if host == "api.openai.com" || host.hasSuffix(".api.openai.com") {
            return RouteOrigin(
                kind: .officialAPI,
                credentialKind: credentialKind == .chatGPTSubscription ? .chatGPTSubscription : .officialAPIKey,
                displayName: "OpenAI · 官方 API",
                host: host,
                confidence: 0.99,
                evidence: ["官方 API 域名"]
            )
        }

        if host == "chatgpt.com" || host.hasSuffix(".chatgpt.com") {
            return RouteOrigin(
                kind: .officialSubscription,
                credentialKind: .chatGPTSubscription,
                displayName: "OpenAI · ChatGPT 官方线路",
                host: host,
                confidence: 0.99,
                evidence: ["官方 ChatGPT 域名"]
            )
        }

        if host == "api.anthropic.com" || host.hasSuffix(".anthropic.com") {
            return RouteOrigin(
                kind: credentialKind == .claudeSubscription ? .officialSubscription : .officialAPI,
                credentialKind: credentialKind == .relayKey ? .providerAPIKey : credentialKind,
                displayName: "Anthropic · 官方 API",
                host: host,
                confidence: 0.99,
                evidence: ["Anthropic 官方 API 域名"]
            )
        }

        if host.hasSuffix(".openai.azure.com") ||
            host.hasSuffix(".services.ai.azure.com") ||
            host.contains("bedrock-runtime") && host.hasSuffix(".amazonaws.com") ||
            host == "aiplatform.googleapis.com" {
            return RouteOrigin(
                kind: .enterpriseCloud,
                credentialKind: .enterpriseIdentity,
                displayName: enterpriseCloudName(for: host),
                host: host,
                confidence: 0.98,
                evidence: ["企业云官方域名"]
            )
        }

        if host == "openrouter.ai" || host.hasSuffix(".openrouter.ai") {
            return RouteOrigin(
                kind: .remoteRelay,
                credentialKind: credentialKind,
                displayName: "OpenRouter · 聚合路由",
                host: host,
                confidence: 0.99,
                evidence: ["OpenRouter 官方域名", "上游 Provider 可能动态选择"]
            )
        }

        if host == "api.portkey.ai" || host.hasSuffix(".portkey.ai") {
            return RouteOrigin(
                kind: .remoteRelay,
                credentialKind: credentialKind,
                displayName: "Portkey AI Gateway",
                host: host,
                confidence: 0.98,
                evidence: ["Portkey 官方网关域名", "网关可配置重试与回退"]
            )
        }

        if isLoopback(host) {
            return classifyLocalGateway(
                host: host,
                port: port,
                declaredName: declaredName,
                credentialKind: credentialKind,
                authEvidence: authEvidence
            )
        }

        if lowerName.contains("sub2api") || host.contains("sub2api") {
            return RouteOrigin(
                kind: .remoteRelay,
                credentialKind: credentialKind,
                displayName: "Sub2API（配置声明）",
                host: host,
                confidence: 0.82,
                evidence: ["自定义远程 Base URL", "Provider 名称或域名包含 Sub2API"] + authEvidence
            )
        }

        if lowerName.contains("litellm") || host.contains("litellm") {
            return declaredRelay(name: "LiteLLM Gateway（配置声明）", host: host, credentialKind: credentialKind, authEvidence: authEvidence)
        }

        if lowerName.contains("new api") || lowerName.contains("new-api") || host.contains("new-api") {
            return declaredRelay(name: "New API（配置声明）", host: host, credentialKind: credentialKind, authEvidence: authEvidence)
        }

        if lowerName.contains("one api") || lowerName.contains("one-api") || host.contains("one-api") {
            return declaredRelay(name: "One API（配置声明）", host: host, credentialKind: credentialKind, authEvidence: authEvidence)
        }

        return RouteOrigin(
            kind: .remoteRelay,
            credentialKind: credentialKind,
            displayName: "远程中转 · 实现未知",
            host: host,
            confidence: 0.72,
            evidence: ["非官方自定义 Base URL", "仅凭兼容 API 无法确定网关实现"] + authEvidence
        )
    }

    private func classifyLocalGateway(
        host: String,
        port: Int?,
        declaredName: String,
        credentialKind: RouteCredentialKind,
        authEvidence: [String]
    ) -> RouteOrigin {
        let signature: (name: String, evidence: String)? = switch port {
        case 8317: ("CLIProxyAPI 类本地网关", "默认端口 :8317；仍需服务指纹确认")
        case 3456: ("Claude Code Router 类本地网关", "默认端口 :3456；仍需服务指纹确认")
        case 7575: ("CCRelay 类本地网关", "默认端口 :7575；仍需服务指纹确认")
        case 4000: ("LiteLLM 类本地网关", "默认端口 :4000；仍需服务指纹确认")
        case 8787: ("Portkey 类本地网关", "默认端口 :8787；仍需服务指纹确认")
        case 8080: ("Sub2API 类本地网关", "常见端口 :8080；不能仅凭端口断言实现")
        case 3000: ("One API / New API 类本地网关", "两者常用 :3000；需服务指纹区分")
        default: nil
        }

        var evidence = ["回环地址 \(host)\(port.map { ":\($0)" } ?? "")"]
        if let signature { evidence.append(signature.evidence) }
        if declaredName != "openai" { evidence.append("Provider: \(declaredName)") }
        evidence.append(contentsOf: authEvidence)

        return RouteOrigin(
            kind: .localGateway,
            credentialKind: credentialKind,
            displayName: signature?.name ?? "本地自建网关",
            host: host,
            confidence: signature == nil ? 0.82 : 0.62,
            evidence: evidence
        )
    }

    private func declaredRelay(
        name: String,
        host: String,
        credentialKind: RouteCredentialKind,
        authEvidence: [String]
    ) -> RouteOrigin {
        RouteOrigin(
            kind: .remoteRelay,
            credentialKind: credentialKind,
            displayName: name,
            host: host,
            confidence: 0.82,
            evidence: ["自定义远程 Base URL", "Provider 名称或域名提供实现线索"] + authEvidence
        )
    }

    private func detectedAIIntegrations(in directories: [URL]) -> [String] {
        var names = Set<String>()
        for directory in directories {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries {
                let name = entry.lastPathComponent.lowercased()
                if name.contains("github.copilot") { names.insert("GitHub Copilot") }
                if name.contains("anthropic") && name.contains("claude") { names.insert("Claude Code") }
                if name.contains("openai") || name.contains("codex") { names.insert("Codex / OpenAI") }
                if name.contains("continue.continue") { names.insert("Continue") }
                if name.contains("claude-dev") || name.contains("cline") { names.insert("Cline") }
                if name.contains("roo-cline") || name.contains("roo-code") { names.insert("Roo Code") }
                if name.contains("codeium") { names.insert("Codeium") }
            }
        }
        return names.sorted()
    }

    private func score(_ client: AIClientDetection) -> Int {
        (client.isFrontmost ? 1_000 : 0) +
            (client.isRunning ? 500 : 0) +
            (client.hasConfiguration ? 200 : 0) +
            (client.isInstalled ? 50 : 0)
    }

    private func clientEvidence(
        isInstalled: Bool,
        isRunning: Bool,
        hasConfiguration: Bool,
        configurationName: String
    ) -> [String] {
        var evidence: [String] = []
        if isRunning { evidence.append("检测到正在运行的应用") }
        else if isInstalled { evidence.append("检测到本机安装") }
        if hasConfiguration { evidence.append("发现 \(configurationName)") }
        return evidence
    }

    private func claudeCredentialKind(
        userStateURL: URL,
        environment: [String: String]
    ) -> RouteCredentialKind {
        if environment.keys.contains("ANTHROPIC_API_KEY") { return .providerAPIKey }
        if environment.keys.contains("ANTHROPIC_AUTH_TOKEN") { return .relayKey }
        guard let state = loadJSONDictionary(at: userStateURL) else { return .unknown }
        if state.keys.contains("oauthAccount") { return .claudeSubscription }
        if state.keys.contains("primaryApiKey") { return .providerAPIKey }
        return .unknown
    }

    private func codexCredentialKind(at url: URL) -> RouteCredentialKind {
        guard let dictionary = loadJSONDictionary(at: url) else { return .unknown }
        if let mode = dictionary["auth_mode"] as? String {
            if mode.lowercased().contains("chatgpt") { return .chatGPTSubscription }
            if mode.lowercased().contains("api") { return .officialAPIKey }
        }
        if dictionary["tokens"] is [String: Any] { return .chatGPTSubscription }
        if dictionary.keys.contains("OPENAI_API_KEY") { return .officialAPIKey }
        return .unknown
    }

    private func credentialEvidence(for kind: RouteCredentialKind) -> [String] {
        switch kind {
        case .chatGPTSubscription: ["代理使用本机 ChatGPT OAuth"]
        case .claudeSubscription: ["代理使用本机 Claude 订阅"]
        case .copilotSubscription: ["通过 GitHub Copilot 账号"]
        case .officialAPIKey: ["代理使用本机 OpenAI API Key"]
        case .providerAPIKey: ["使用 Provider API Key"]
        case .relayKey: ["Provider 通过环境变量读取网关 Key"]
        case .vendorAccount: ["使用客户端账号"]
        case .enterpriseIdentity: ["使用企业云身份"]
        case .noAuthentication: ["自定义 Provider 未声明客户端鉴权"]
        case .unknown: ["凭据类型待确认"]
        }
    }

    private func enterpriseCloudName(for host: String) -> String {
        if host.contains("azure") { return "Azure OpenAI / AI Foundry" }
        if host.contains("amazonaws") { return "Amazon Bedrock" }
        return "Google Vertex AI"
    }

    private func isLoopback(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private func isTruthy(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["1", "true", "yes", "on"].contains(value.lowercased())
    }

    private func host(from rawURL: String?) -> String? {
        guard let rawURL, !rawURL.isEmpty else { return nil }
        let normalized = rawURL.contains("://") ? rawURL : "https://\(rawURL)"
        return URLComponents(string: normalized)?.host?.lowercased()
    }

    private func hasInstalledApplication(named name: String) -> Bool {
        [
            "/Applications/\(name)",
            homeDirectory.appendingPathComponent("Applications/\(name)").path
        ].contains(where: fileManager.fileExists(atPath:))
    }

    private func executableExists(at paths: [String]) -> Bool {
        paths.contains { fileManager.isExecutableFile(atPath: $0) }
    }

    private func applicationSupportURL(_ relativePath: String) -> URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(relativePath)
    }

    private func codexHomeURL() -> URL {
        if let custom = ProcessInfo.processInfo.environment["CODEX_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return homeDirectory.appendingPathComponent(".codex", isDirectory: true)
    }

    private func loadJSONDictionary(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary
    }

    private func jsonLikeStringValue(for key: String, in text: String) -> String? {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let pattern = #"[\"']"# + escapedKey + #"[\"']\s*:\s*[\"']([^\"']+)[\"']"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private func scanCodexConfig(at url: URL) -> CodexConfigScan {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return CodexConfigScan()
        }

        var scan = CodexConfigScan()
        var section = ""

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                continue
            }

            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            let value = unquote(String(line[line.index(after: equals)...]))

            if section.isEmpty {
                switch key {
                case "model": scan.model = value
                case "model_provider": scan.modelProvider = value
                case "model_reasoning_effort": scan.modelReasoningEffort = value
                case "openai_base_url": scan.openAIBaseURL = value
                default: break
                }
                continue
            }

            guard section.hasPrefix("model_providers.") else { continue }
            let providerID = String(section.dropFirst("model_providers.".count))
            guard !providerID.contains(".") else { continue }
            var provider = scan.providers[providerID] ?? ProviderScan()
            switch key {
            case "name": provider.name = value
            case "base_url": provider.baseURL = value
            case "wire_api": provider.wireAPI = value
            case "requires_openai_auth": provider.requiresOpenAIAuth = value.lowercased() == "true"
            case "env_key": provider.usesEnvironmentKey = !value.isEmpty
            default: break
            }
            scan.providers[providerID] = provider
        }

        return scan
    }

    private func stripComment(_ line: String) -> String {
        var quoted = false
        var escaped = false
        for index in line.indices {
            let character = line[index]
            if character == "\\" && quoted {
                escaped.toggle()
                continue
            }
            if character == "\"" && !escaped { quoted.toggle() }
            if character == "#" && !quoted { return String(line[..<index]) }
            escaped = false
        }
        return line
    }

    private func unquote(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard value.count >= 2, value.first == "\"", value.last == "\"" else { return value }
        return String(value.dropFirst().dropLast())
    }
}

private struct CodexConfigScan {
    var model: String?
    var modelProvider: String?
    var modelReasoningEffort: String?
    var openAIBaseURL: String?
    var providers: [String: ProviderScan] = [:]
}

private struct ProviderScan {
    var name: String?
    var baseURL: String?
    var wireAPI: String?
    var requiresOpenAIAuth = false
    var usesEnvironmentKey = false
}
