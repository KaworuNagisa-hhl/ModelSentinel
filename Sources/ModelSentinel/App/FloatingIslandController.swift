import AppKit
import Combine
import SwiftUI

@MainActor
final class FloatingIslandController: NSObject {
    private static let expandedWidth: CGFloat = 372
    private static let compactNotchOverlap: CGFloat = 8

    private let store: MonitorStore
    private let panel: NSPanel
    private let sensorPanel: NSPanel
    private let hoverSensor = NotchHoverSensorView(frame: .zero)
    private var cancellables = Set<AnyCancellable>()
    private var hoverTask: Task<Void, Never>?
    private var frameAnimationTask: Task<Void, Never>?
    private var isSensorHovered = false
    private var isContentHovered = false
    private let pinsExpandedForPreview = ProcessInfo.processInfo.arguments.contains("--expanded")

    private struct NotchGeometry {
        let layout: IslandDisplayLayout
        let centerX: CGFloat
        let expandedTopY: CGFloat
        let sensorFrame: NSRect
        let compactStatusFrame: NSRect
    }

    init(store: MonitorStore) {
        self.store = store
        panel = Self.makePanel()
        sensorPanel = Self.makePanel()
        super.init()

        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true

        sensorPanel.hasShadow = false
        sensorPanel.acceptsMouseMovedEvents = true
        sensorPanel.contentView = hoverSensor
        hoverSensor.onHoverChange = { [weak self] inside in
            self?.handleSensorHover(inside)
        }

        let view = IslandView(
            store: store,
            onToggle: { [weak self] in self?.toggleExpanded() },
            onHoverChange: { [weak self] inside in self?.handleContentHover(inside) }
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        updatePresentation(animated: false)
        observeScreenChanges()
        observeStore()
    }

    deinit {
        hoverTask?.cancel()
        frameAnimationTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    func show() {
        store.isVisible = true
        updatePresentation(animated: true)
    }

    func hide() {
        store.isVisible = false
        frameAnimationTask?.cancel()
        panel.orderOut(nil)
        sensorPanel.orderOut(nil)
    }

    func toggleExpanded() {
        hoverTask?.cancel()
        store.toggleExpanded()
    }

    func refresh() {
        store.isVisible ? show() : hide()
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        return panel
    }

    private func updatePresentation(animated: Bool) {
        guard store.isVisible else {
            panel.orderOut(nil)
            sensorPanel.orderOut(nil)
            return
        }

        let screen = targetScreen()
        let notch = notchGeometry(for: screen)
        store.displayLayout = notch?.layout ?? .standard

        if let notch {
            sensorPanel.setFrame(notch.sensorFrame, display: true)
            if pinsExpandedForPreview && store.isExpanded {
                sensorPanel.orderOut(nil)
            } else {
                sensorPanel.orderFrontRegardless()
            }

            guard store.isExpanded else {
                setPanelFrame(notch.compactStatusFrame, animated: animated)
                panel.orderFrontRegardless()
                return
            }

            let frame = expandedFrame(top: notch.expandedTopY, centerX: notch.centerX)
            setPanelFrame(frame, animated: animated)
            panel.orderFrontRegardless()
            return
        }

        sensorPanel.orderOut(nil)
        let frame = standardFrame(for: screen)
        setPanelFrame(frame, animated: animated)
        panel.orderFrontRegardless()
    }

    private func setPanelFrame(_ frame: NSRect, animated: Bool) {
        frameAnimationTask?.cancel()
        guard animated, panel.isVisible else {
            panel.setFrame(frame, display: true)
            return
        }

        let start = panel.frame
        guard start != frame else { return }
        let frameCount = 24
        frameAnimationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for step in 1...frameCount {
                do {
                    try await Task.sleep(for: .milliseconds(16))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                let progress = CGFloat(step) / CGFloat(frameCount)
                let eased = progress < 0.5
                    ? 4 * progress * progress * progress
                    : 1 - pow(-2 * progress + 2, 3) / 2
                let current = NSRect(
                    x: start.origin.x + (frame.origin.x - start.origin.x) * eased,
                    y: start.origin.y + (frame.origin.y - start.origin.y) * eased,
                    width: start.width + (frame.width - start.width) * eased,
                    height: start.height + (frame.height - start.height) * eased
                )
                panel.setFrame(current, display: true)
            }
            panel.setFrame(frame, display: true)
        }
    }

    private func expandedFrame(top: CGFloat, centerX: CGFloat) -> NSRect {
        let height: CGFloat = store.displayLayout.isNotched
            ? 264 + store.displayLayout.compactHeight
            : 276
        let size = NSSize(width: Self.expandedWidth, height: height)
        return NSRect(
            x: centerX - size.width / 2,
            y: top - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func standardFrame(for screen: NSScreen) -> NSRect {
        if store.isExpanded {
            return expandedFrame(top: screen.visibleFrame.maxY - 8, centerX: screen.frame.midX)
        }

        let layout = IslandDisplayLayout.standard
        return NSRect(
            x: screen.frame.midX - layout.compactWidth / 2,
            y: screen.visibleFrame.maxY - layout.compactHeight - 8,
            width: layout.compactWidth,
            height: layout.compactHeight
        )
    }

    private func targetScreen() -> NSScreen {
        NSScreen.main ?? NSScreen.screens.first(where: {
            guard let area = $0.auxiliaryTopLeftArea else { return false }
            return !area.isEmpty
        }) ?? NSScreen.screens[0]
    }

    private func notchGeometry(for screen: NSScreen) -> NotchGeometry? {
        guard screen.safeAreaInsets.top > 0,
              let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea,
              !leftArea.isEmpty,
              !rightArea.isEmpty else {
            return nil
        }

        let notchWidth = rightArea.minX - leftArea.maxX
        guard notchWidth > 40 else { return nil }
        let menuBarBottomY = screen.visibleFrame.maxY
        let sensorHeight = max(1, screen.frame.maxY - menuBarBottomY)
        let compactLeftX = screen.frame.midX - Self.expandedWidth / 2
        let compactStatusWidth = leftArea.maxX - compactLeftX + Self.compactNotchOverlap
        let layout = IslandDisplayLayout(
            isNotched: true,
            compactHeight: sensorHeight,
            leftWingWidth: compactStatusWidth,
            notchGapWidth: notchWidth,
            rightWingWidth: 0
        )

        return NotchGeometry(
            layout: layout,
            centerX: screen.frame.midX,
            expandedTopY: screen.frame.maxY,
            sensorFrame: NSRect(
                x: screen.frame.midX - notchWidth / 2,
                y: menuBarBottomY,
                width: notchWidth,
                height: sensorHeight
            ),
            compactStatusFrame: NSRect(
                x: compactLeftX,
                y: menuBarBottomY,
                width: layout.leftWingWidth,
                height: sensorHeight
            )
        )
    }

    private func handleSensorHover(_ inside: Bool) {
        isSensorHovered = inside
        scheduleHoverStateUpdate()
    }

    private func handleContentHover(_ inside: Bool) {
        isContentHovered = inside
        scheduleHoverStateUpdate()
    }

    private func scheduleHoverStateUpdate() {
        guard store.displayLayout.isNotched else { return }
        guard !pinsExpandedForPreview else { return }
        hoverTask?.cancel()

        let shouldExpand = isSensorHovered || isContentHovered
        guard shouldExpand != store.isExpanded else { return }
        let delay = shouldExpand ? Duration.milliseconds(150) : Duration.milliseconds(620)

        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            let stillShouldExpand = isSensorHovered || isContentHovered
            guard stillShouldExpand == shouldExpand else { return }
            store.isExpanded = shouldExpand
        }
    }

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func observeStore() {
        store.$isExpanded
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updatePresentation(animated: true)
                }
            }
            .store(in: &cancellables)

        store.$isVisible
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updatePresentation(animated: true)
                }
            }
            .store(in: &cancellables)
    }

    @objc private func screenConfigurationChanged() {
        updatePresentation(animated: false)
    }
}

private final class NotchHoverSensorView: NSView {
    var onHoverChange: ((Bool) -> Void)?
    private var trackingAreaReference: NSTrackingArea?

    override var isOpaque: Bool { false }

    override func updateTrackingAreas() {
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaReference = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
    }
}
