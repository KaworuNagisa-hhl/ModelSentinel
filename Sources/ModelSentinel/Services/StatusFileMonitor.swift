import Foundation

actor StatusFileMonitor {
    static let shared = StatusFileMonitor()

    let statusURL: URL
    private var watchTask: Task<Void, Never>?
    private var lastModificationDate: Date?
    private let maximumFileAge: TimeInterval = 120
    private let maximumSnapshotAge: TimeInterval = 300

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        statusURL = base
            .appendingPathComponent("ModelSentinel", isDirectory: true)
            .appendingPathComponent("status.json")
    }

    func start() {
        guard watchTask == nil else { return }
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.readIfChanged()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        watchTask?.cancel()
        watchTask = nil
    }

    private func readIfChanged() async {
        let shouldRead = await MainActor.run { MonitorStore.shared.isWatchingFile }
        guard shouldRead else { return }

        let path = statusURL.path
        guard FileManager.default.fileExists(atPath: path) else { return }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            let modificationDate = attributes[.modificationDate] as? Date
            guard modificationDate != lastModificationDate else { return }
            lastModificationDate = modificationDate

            if let modificationDate,
               !isFresh(modificationDate, maximumAge: maximumFileAge) {
                await MainActor.run {
                    MonitorStore.shared.lastReadError = "已忽略过期探针状态"
                }
                return
            }

            let data = try Data(contentsOf: statusURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(RouteSnapshot.self, from: data)
            guard isFresh(snapshot.updatedAt, maximumAge: maximumSnapshotAge) else {
                await MainActor.run {
                    MonitorStore.shared.lastReadError = "已忽略时间戳过期的探针结果"
                }
                return
            }
            await MonitorStore.shared.apply(snapshot)
        } catch {
            await MainActor.run {
                MonitorStore.shared.lastReadError = error.localizedDescription
            }
        }
    }

    private func isFresh(_ date: Date, maximumAge: TimeInterval) -> Bool {
        let age = Date().timeIntervalSince(date)
        return age >= -60 && age <= maximumAge
    }
}
