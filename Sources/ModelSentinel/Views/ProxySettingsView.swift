import SwiftUI

struct ProxySettingsView: View {
    @ObservedObject var store: ProxyStore
    @State private var confirmsActiveProbe = false

    var body: some View {
        Form {
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

            Section("主动能力探针") {
                LabeledContent("探针状态", value: store.activeProbeState.label)
                Text("仅在响应模型字段缺失或不可信时使用。每次运行会额外占用 1 个 Codex 本地任务；只保存通过数量和耗时。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button("运行主动能力探针…") {
                    confirmsActiveProbe = true
                }
                .disabled(store.activeProbeState == .running)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 580)
        .padding(16)
        .alert("运行主动能力探针？", isPresented: $confirmsActiveProbe) {
            Button("取消", role: .cancel) {}
            Button("运行") {
                store.runActiveProbe()
            }
        } message: {
            Text("将额外执行 1 个 Codex 本地任务，并计入当前账号或中转站用量。Plus 额度紧张时建议取消，优先使用零额外用量的本地响应代理。不会读取或保存你的对话、代码或凭据。")
        }
    }
}
