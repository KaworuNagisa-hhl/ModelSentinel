import SwiftUI

struct IslandView: View {
    @ObservedObject var store: MonitorStore
    let onToggle: () -> Void
    let onHoverChange: (Bool) -> Void

    var body: some View {
        Group {
            if store.displayLayout.isNotched {
                notchedContent
            } else if store.isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else {
                floatingIdleContent
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .onHover(perform: onHoverChange)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "模型线路状态：\(statusTitle)；当前会话：\(store.snapshot.claimedModel)；\(store.snapshot.note)"
        )
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: store.isExpanded)
        .animation(.easeInOut(duration: 0.22), value: store.snapshot.health)
    }

    private var notchedContent: some View {
        ZStack(alignment: .topLeading) {
            notchedSurface

            if store.isExpanded {
                expandedContent
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: -8)),
                            removal: .opacity
                        )
                    )
            } else {
                Color.clear
                    .frame(
                        width: store.displayLayout.leftWingWidth,
                        height: store.displayLayout.compactHeight
                    )
                    .accessibilityLabel("收起状态：\(compactStatusLabel)")
            }

            StatusDot(
                health: store.snapshot.health,
                tint: store.snapshot.health.compactIndicatorColor
            )
            .frame(width: 30, height: 30)
            .offset(
                x: 16,
                y: store.isExpanded
                    ? store.displayLayout.compactHeight
                    : (store.displayLayout.compactHeight - 30) / 2
            )
            .zIndex(2)
        }
        .frame(
            width: store.isExpanded ? 372 : store.displayLayout.leftWingWidth,
            height: store.isExpanded
                ? 264 + store.displayLayout.compactHeight
                : store.displayLayout.compactHeight,
            alignment: .topLeading
        )
    }

    private var notchedSurface: some View {
        let shape = UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 0,
                bottomLeading: store.isExpanded ? 25 : 16,
                bottomTrailing: store.isExpanded ? 25 : 0,
                topTrailing: 0
            ),
            style: .continuous
        )
        return glassSurface(shape: shape)
            .frame(
                width: store.isExpanded ? 372 : store.displayLayout.leftWingWidth,
                height: store.isExpanded
                    ? 264 + store.displayLayout.compactHeight
                    : store.displayLayout.compactHeight
            )
    }

    private var compactStatusLabel: String {
        switch store.snapshot.health {
        case .verified:
            "正常"
        case .configured, .probing, .warning:
            "疑似或等待验证"
        case .mismatch, .offline:
            "异常"
        }
    }

    private var floatingIdleContent: some View {
        HStack(spacing: 9) {
            StatusDot(health: store.snapshot.health)

            Text(statusTitle)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))

            Spacer(minLength: 4)

            Text(store.snapshot.confidence.percentText)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(store.snapshot.health.color)
        }
        .padding(.horizontal, 12)
        .frame(width: store.displayLayout.compactWidth, height: store.displayLayout.compactHeight)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(.black.opacity(0.62)))
                .overlay(Capsule().stroke(.white.opacity(0.13), lineWidth: 0.6))
                .shadow(color: .black.opacity(0.28), radius: 10, y: 5)
        }
    }

    private var expandedContent: some View {
        VStack(spacing: 11) {
            header
            modelCard
            routeAndCredentialCard

            HStack(spacing: 7) {
                ForEach(Array(store.snapshot.evidence.prefix(4))) { metric in
                    EvidenceBadge(metric: metric, tint: store.snapshot.health.color)
                }
            }

            footer
        }
        .padding(.horizontal, 16)
        .padding(
            .top,
            store.displayLayout.isNotched
                ? store.displayLayout.compactHeight
                : 8
        )
        .padding(.bottom, 13)
        .frame(
            width: 372,
            height: store.displayLayout.isNotched
                ? 264 + store.displayLayout.compactHeight
                : 276,
            alignment: .top
        )
        .background {
            if !store.displayLayout.isNotched {
                expandedSurface
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Group {
                if store.displayLayout.isNotched {
                    Color.clear
                } else {
                    StatusDot(
                        health: store.snapshot.health,
                        tint: store.snapshot.health.compactIndicatorColor
                    )
                }
            }
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                Text(headerSubtitle)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("来源可信度")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(store.snapshot.confidence.percentText)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                Text(modelVerificationLabel)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(modelVerificationColor)
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 94, minHeight: 36)
            .background(
                .white.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
    }

    private var modelVerificationLabel: String {
        switch store.snapshot.health {
        case .verified where store.snapshot.modelDetails?.responseModelID != nil:
            "响应声明一致"
        case .mismatch:
            "返回模型不匹配"
        case .warning:
            "返回模型存疑"
        case .offline:
            "响应离线"
        case .probing:
            "返回模型验证中"
        case _ where store.snapshot.modelDetails?.responseObserved == true:
            "模型字段未提供"
        default:
            "返回模型待验证"
        }
    }

    private var modelVerificationColor: Color {
        switch store.snapshot.health {
        case .verified where store.snapshot.modelDetails?.responseModelID != nil:
            .green
        case .mismatch, .offline:
            .red
        case .probing:
            .cyan
        default:
            .yellow
        }
    }

    private var headerSubtitle: String {
        let client = store.snapshot.client?.displayName ?? "客户端待识别"
        let host = store.snapshot.client?.hostApplication.map { " · \($0)" } ?? ""
        let origin = store.snapshot.origin?.displayName ?? store.snapshot.provider
        return "\(client)\(host) · \(origin)"
    }

    private var statusTitle: String {
        if store.snapshot.health == .configured,
           let client = store.snapshot.client,
           client.isRunning {
            return "\(client.displayName) 使用中"
        }
        return store.snapshot.health.label
    }

    private var modelCard: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                modelDetail(
                    label: "当前请求 / 会话 ID",
                    value: store.snapshot.modelDetails?.requestedModelID ?? store.snapshot.claimedModel
                )
                modelDetail(
                    label: "服务端返回模型",
                    value: responseModelText,
                    pending: store.snapshot.modelDetails?.responseModelID == nil
                )
            }

            HStack(spacing: 8) {
                modelDetail(
                    label: "行为匹配",
                    value: store.snapshot.modelDetails?.behavioralMatch ?? store.snapshot.matchedFamily
                )
                modelDetail(
                    label: "推理档位 · 协议",
                    value: reasoningAndProtocol
                )
            }

            HStack(spacing: 5) {
                Text("Provider")
                    .foregroundStyle(.tertiary)
                Text(store.snapshot.modelDetails?.providerID ?? "待识别")
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("上下文")
                    .foregroundStyle(.tertiary)
                Text(contextWindowText)
                Spacer()
                if store.snapshot.latencyMS > 0 {
                    Text("\(store.snapshot.latencyMS) ms")
                        .monospacedDigit()
                } else {
                    Text("等待响应")
                }
            }
            .font(.system(size: 8.5, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(height: 91)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func modelDetail(label: String, value: String, pending: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(pending ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reasoningAndProtocol: String {
        let reasoning = store.snapshot.modelDetails?.reasoningEffort ?? "待识别"
        let protocolName = store.snapshot.modelDetails?.wireAPI ?? "未声明"
        return "\(reasoning) · \(protocolName)"
    }

    private var responseModelText: String {
        if let responseModelID = store.snapshot.modelDetails?.responseModelID {
            return responseModelID
        }
        if store.snapshot.modelDetails?.responseObserved == true {
            return "真实响应已确认 · 无模型字段"
        }
        return store.snapshot.health == .probing ? "正在采集响应证据" : "等待下一次响应"
    }

    private var contextWindowText: String {
        guard let tokens = store.snapshot.modelDetails?.contextWindowTokens else {
            return "待探测"
        }
        return tokens.formatted() + " tokens"
    }

    private var routeAndCredentialCard: some View {
        HStack(spacing: 8) {
            infoChip(
                symbol: "point.3.connected.trianglepath.dotted",
                label: "线路",
                value: store.snapshot.origin?.kind.label ?? "待识别"
            )
            infoChip(
                symbol: "key.horizontal.fill",
                label: "凭据",
                value: store.snapshot.origin?.credentialKind?.label ?? "待识别"
            )
        }
    }

    private func infoChip(symbol: String, label: String, value: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 38)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(store.snapshot.health.color)
                .frame(width: 5, height: 5)
                .shadow(color: store.snapshot.health.color.opacity(0.7), radius: 3)
            Text(store.snapshot.note)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(store.snapshot.updatedAt, style: .time)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var expandedSurface: some View {
        if store.displayLayout.isNotched {
            glassSurface(
                shape: UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: 0,
                        bottomLeading: 25,
                        bottomTrailing: 25,
                        topTrailing: 0
                    ),
                    style: .continuous
                )
            )
        } else {
            glassSurface(
                shape: RoundedRectangle(cornerRadius: 25, style: .continuous)
            )
        }
    }

    private func glassSurface<S: Shape>(shape: S) -> some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay {
                shape
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black.opacity(0.98), location: 0.18),
                            .init(color: .black.opacity(0.90), location: 0.52),
                            .init(color: .black.opacity(0.86), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .clipShape(shape)
    }
}

private struct EvidenceBadge: View {
    let metric: EvidenceMetric
    let tint: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(metric.value.percentText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
            HStack(spacing: 3) {
                Circle()
                    .fill(metric.value >= 0.75 ? tint : .yellow)
                    .frame(width: 4, height: 4)
                Text(metric.name)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 32)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
