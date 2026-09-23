import SwiftUI

struct ProxySettingsView: View {
    @ObservedObject var store: ProxyStore
    @ObservedObject var monitorStore: MonitorStore
    @State private var confirmsActiveProbe = false
    @State private var confirmsActiveMonitoring = false

    var body: some View {
        Form {
            Section("检测模式") {
                Picker(
                    "模式",
                    selection: Binding(
                        get: { monitorStore.detectionMode },
                        set: { requestedMode in
                            if requestedMode == .active,
                               monitorStore.detectionMode != .active {
                                confirmsActiveMonitoring = true
                            } else {
                                monitorStore.setDetectionMode(requestedMode)
                            }
                        }
                    )
                ) {
                    ForEach(DetectionMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(monitorStore.detectionMode.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if monitorStore.detectionMode == .active {
                    LabeledContent(
                        "当前支持状态",
                        value: store.activeProbeAvailability(snapshot: monitorStore.snapshot)
                    )
                    LabeledContent("自动探针冷却", value: "同一客户端、模型和线路 6 小时")
                    LabeledContent("探针状态", value: store.activeProbeState.label)

                    Button("立即主动验证…") {
                        confirmsActiveProbe = true
                    }
                    .disabled(
                        store.activeProbeState == .running ||
                            !store.supportsActiveProbe(snapshot: monitorStore.snapshot)
                    )
                }

                Text("被动检测不会新增模型请求。主动监测会额外执行极短的独立任务；当前自动探针仅支持 Codex，Qoder 等客户端仍需等待正常响应或接入本地代理。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section("本地响应代理") {
                Toggle(
                    "启用本地代理",
                    isOn: Binding(
                        get: { store.isEnabled },
                        set: { store.setEnabled($0) }
                    )
                )

                TextField("上游 Base URL", text: $store.upstreamBaseURL)
                    .textFieldStyle(.roundedBorder)

                Stepper(value: $store.listenPort, in: 1_024...65_535) {
                    LabeledContent("本地端口", value: store.listenPort.formatted())
                }

                LabeledContent("运行状态", value: store.runtimeState.label)
                LabeledContent("客户端 Base URL", value: store.localBaseURL)

                HStack {
                    Button("应用并重启代理") {
                        store.applyAndRestart()
                    }
                    .disabled(store.isEnabled && !store.canStart)

                    Button("复制本地地址") {
                        store.copyLocalBaseURL()
                    }
                }
            }

            Section("检测范围") {
                Text("代理仅监听 127.0.0.1，转发请求时不会记录 Authorization、提示词或回答正文。内存中只提取请求模型、响应模型、响应 ID 与延迟。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let observation = store.lastObservation {
                    LabeledContent("最近请求", value: observation.requestedModelID ?? "未声明")
                    LabeledContent("响应声明", value: observation.responseModelID ?? "未提供")
                    LabeledContent("上游", value: observation.upstreamHost)
                    LabeledContent("耗时", value: "\(observation.latencyMS) ms")
                }
            }

        }
        .formStyle(.grouped)
        .frame(width: 560, height: 680)
        .padding(16)
        .alert("开启主动监测？", isPresented: $confirmsActiveMonitoring) {
            Button("取消", role: .cancel) {}
            Button("开启并验证") {
                monitorStore.setDetectionMode(.active)
                store.runActiveProbeNow()
            }
        } message: {
            Text("开启后，ModelSentinel 会在检测到新的 Codex 客户端、模型或线路组合时自动发起一个极短探针，同一组合 6 小时内不重复。每次探针都会计入账号额度或中转站账单。合成提示约 100 个输入 Token，Codex CLI 自身上下文及少量输出另行计入。")
        }
        .alert("运行主动能力探针？", isPresented: $confirmsActiveProbe) {
            Button("取消", role: .cancel) {}
            Button("运行") {
                store.runActiveProbeNow()
            }
        } message: {
            Text("将立即额外执行 1 个 Codex 本地任务，并重新开始 6 小时冷却。它会计入当前账号或中转站用量；不会读取或保存你的对话、代码或凭据。Plus 额度紧张时建议取消并使用被动检测。")
        }
    }
}
