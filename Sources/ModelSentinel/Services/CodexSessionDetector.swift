import Foundation

struct CodexSessionObservation: Sendable {
    let modelID: String?
    let reasoningEffort: String?
    let contextWindowTokens: Int?
    let isTaskActive: Bool
    let responseID: String?
    let hasAssistantResponse: Bool
    let updatedAt: Date

    var hasResponseEvidence: Bool {
        responseID != nil || hasAssistantResponse
    }
}

actor CodexSessionDetector {
    static let shared = CodexSessionDetector()

    private let fileManager: FileManager
    private let sessionsDirectory: URL
    private let maximumTailBytes: UInt64 = 8 * 1024 * 1024

    private struct TurnEvidence {
        var lastRecordIndex = 0
        var modelID: String?
        var reasoningEffort: String?
        var contextWindowTokens: Int?
        var isTaskActive: Bool?
        var responseID: String?
        var hasAssistantResponse = false
    }

    init(fileManager: FileManager = .default, homeDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.sessionsDirectory = (homeDirectory ?? fileManager.homeDirectoryForCurrentUser)
            .appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    func latestObservation(now: Date = .now) -> CodexSessionObservation? {
        guard let session = latestSessionFile(now: now),
              let lines = tailLines(at: session.url) else {
            return nil
        }

        var turns: [String: TurnEvidence] = [:]

        for (index, line) in lines.enumerated() {
            let isTurnContext = line.contains("\"type\":\"turn_context\"")
            let isTaskLifecycle = line.contains("\"type\":\"event_msg\"") &&
                (line.contains("\"type\":\"task_started\"") ||
                    line.contains("\"type\":\"task_complete\""))
            let isTokenUsage = line.contains("\"type\":\"token_usage_record\"")
            let isResponseItem = line.contains("\"type\":\"response_item\"")
            guard isTurnContext || isTaskLifecycle || isTokenUsage || isResponseItem else { continue }
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = object["payload"] as? [String: Any] else {
                continue
            }

            let recordType = object["type"] as? String
            let payloadType = payload["type"] as? String
            let metadata = payload["internal_chat_message_metadata_passthrough"] as? [String: Any]
            guard let turnID = payload["turn_id"] as? String ?? metadata?["turn_id"] as? String else {
                continue
            }
            var evidence = turns[turnID] ?? TurnEvidence()
            evidence.lastRecordIndex = index

            if recordType == "turn_context" {
                evidence.modelID = payload["model"] as? String ?? evidence.modelID
                evidence.reasoningEffort = payload["effort"] as? String ?? evidence.reasoningEffort
            }

            if recordType == "event_msg", payloadType == "task_started" {
                evidence.contextWindowTokens = payload["model_context_window"] as? Int
                    ?? evidence.contextWindowTokens
                evidence.isTaskActive = true
            } else if recordType == "event_msg", payloadType == "task_complete" {
                evidence.isTaskActive = false
            }

            if recordType == "token_usage_record" {
                evidence.responseID = payload["response_id"] as? String ?? evidence.responseID
            }

            if recordType == "response_item",
               payloadType == "message",
               payload["role"] as? String == "assistant" {
                evidence.hasAssistantResponse = true
            }
            turns[turnID] = evidence
        }

        let latestTurn = turns.values.max { $0.lastRecordIndex < $1.lastRecordIndex }
        let latestCompletedTurn = turns.values
            .filter { $0.isTaskActive == false }
            .max { $0.lastRecordIndex < $1.lastRecordIndex }
        guard let latestTurn else { return nil }

        let completedEvidence = latestCompletedTurn ?? (
            latestTurn.isTaskActive == false ? latestTurn : nil
        )
        return CodexSessionObservation(
            modelID: latestTurn.modelID ?? completedEvidence?.modelID,
            reasoningEffort: latestTurn.reasoningEffort ?? completedEvidence?.reasoningEffort,
            contextWindowTokens: latestTurn.contextWindowTokens ?? completedEvidence?.contextWindowTokens,
            isTaskActive: latestTurn.isTaskActive ?? false,
            responseID: completedEvidence?.responseID,
            hasAssistantResponse: completedEvidence?.hasAssistantResponse ?? false,
            updatedAt: session.modificationDate
        )
    }

    private func latestSessionFile(now: Date) -> (url: URL, modificationDate: Date)? {
        let calendar = Calendar.current
        let candidateDates = [now, calendar.date(byAdding: .day, value: -1, to: now)].compactMap { $0 }
        var candidates: [(URL, Date)] = []

        for date in candidateDates {
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = components.year,
                  let month = components.month,
                  let day = components.day else { continue }
            let directory = sessionsDirectory
                .appendingPathComponent(String(format: "%04d", year), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", month), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", day), isDirectory: true)
            guard let urls = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in urls where url.pathExtension == "jsonl" && isPrimarySession(at: url) {
                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                      let modificationDate = values.contentModificationDate else { continue }
                candidates.append((url, modificationDate))
            }
        }

        return candidates.max { $0.1 < $1.1 }
    }

    private func isPrimarySession(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return true }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 512 * 1024),
              let newline = data.firstIndex(of: 0x0A),
              let object = try? JSONSerialization.jsonObject(with: data[..<newline]) as? [String: Any],
              object["type"] as? String == "session_meta",
              let payload = object["payload"] as? [String: Any] else {
            return true
        }

        if payload["parent_thread_id"] != nil {
            return false
        }
        if let source = payload["source"] as? [String: Any], source["subagent"] != nil {
            return false
        }
        if let threadSource = payload["thread_source"] as? String,
           threadSource != "user" {
            return false
        }
        return true
    }

    private func tailLines(at url: URL) -> [Substring]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let fileSize = try? handle.seekToEnd() else { return nil }
        let offset = fileSize > maximumTailBytes ? fileSize - maximumTailBytes : 0
        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.readToEnd(),
                  var text = String(data: data, encoding: .utf8) else { return nil }
            if offset > 0, let firstNewline = text.firstIndex(of: "\n") {
                text.removeSubrange(text.startIndex...firstNewline)
            }
            return text.split(whereSeparator: \.isNewline)
        } catch {
            return nil
        }
    }
}
