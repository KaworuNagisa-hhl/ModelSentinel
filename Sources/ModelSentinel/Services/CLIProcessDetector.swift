import Foundation

struct CLIProcessObservation: Sendable {
    let executableID: String
    let processID: Int
    let parentProcessID: Int
    let executablePath: String
    let hostApplication: String?
    let isInternalHelper: Bool
}

struct CLIProcessDetector {
    func scan() -> [CLIProcessObservation] {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,ucomm=,comm="]
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return []
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        let records = output.split(whereSeparator: \.isNewline).compactMap(parseRecord)
        let recordByPID = Dictionary(uniqueKeysWithValues: records.map { ($0.processID, $0) })

        return records.compactMap { record in
            guard let executableID = supportedExecutableID(for: record) else { return nil }
            let ancestry = ancestry(for: record, records: recordByPID)
            return CLIProcessObservation(
                executableID: executableID,
                processID: record.processID,
                parentProcessID: record.parentProcessID,
                executablePath: record.executablePath,
                hostApplication: hostApplication(in: ancestry),
                isInternalHelper: ancestry.contains(where: isModelSentinelOrAIClientHelper)
            )
        }
    }

    private func parseRecord(_ rawLine: Substring) -> ProcessRecord? {
        let fields = rawLine.split(maxSplits: 3, whereSeparator: \.isWhitespace)
        guard fields.count == 4,
              let processID = Int(fields[0]),
              let parentProcessID = Int(fields[1]) else {
            return nil
        }
        return ProcessRecord(
            processID: processID,
            parentProcessID: parentProcessID,
            shortName: String(fields[2]),
            executablePath: String(fields[3])
        )
    }

    private func supportedExecutableID(for record: ProcessRecord) -> String? {
        let shortName = record.shortName.lowercased()
        let pathName = URL(fileURLWithPath: record.executablePath).lastPathComponent.lowercased()
        let names = [shortName, pathName]

        if names.contains("codex") { return "codex-cli" }
        if names.contains("claude") { return "claude-code" }
        if names.contains("gemini") { return "gemini-cli" }
        if names.contains("aider") || names.contains("aider-chat") { return "aider" }
        if names.contains("opencode") { return "opencode" }
        if names.contains("amp") { return "amp" }
        if names.contains("qwen") || names.contains("qwen-code") { return "qwen-code" }
        return nil
    }

    private func ancestry(
        for record: ProcessRecord,
        records: [Int: ProcessRecord]
    ) -> [ProcessRecord] {
        var result: [ProcessRecord] = []
        var nextPID = record.parentProcessID
        var visited = Set<Int>()

        while nextPID > 1, result.count < 16, !visited.contains(nextPID) {
            visited.insert(nextPID)
            guard let parent = records[nextPID] else { break }
            result.append(parent)
            nextPID = parent.parentProcessID
        }
        return result
    }

    private func hostApplication(in ancestry: [ProcessRecord]) -> String? {
        for record in ancestry {
            let candidate = "\(record.shortName) \(record.executablePath)".lowercased()
            if candidate.contains("terminal.app") { return "Terminal" }
            if candidate.contains("iterm") { return "iTerm" }
            if candidate.contains("warp.app") { return "Warp" }
            if candidate.contains("visual studio code.app") || candidate.contains("code helper") {
                return "Visual Studio Code"
            }
            if candidate.contains("cursor.app") || candidate.contains("cursor helper") { return "Cursor" }
            if candidate.contains("windsurf.app") || candidate.contains("windsurf helper") { return "Windsurf" }
            if candidate.contains("zed.app") { return "Zed" }
            if candidate.contains("android studio.app") { return "Android Studio" }
            if candidate.contains("deveco-studio.app") { return "DevEco Studio" }
            if candidate.contains("intellij idea.app") { return "IntelliJ IDEA" }
        }
        return nil
    }

    private func isModelSentinelOrAIClientHelper(_ record: ProcessRecord) -> Bool {
        let candidate = "\(record.shortName) \(record.executablePath)".lowercased()
        return candidate.contains("modelsentinel.app") ||
            candidate.contains("chatgpt.app") ||
            candidate.contains("codex framework") ||
            candidate.contains("node_repl") ||
            candidate.contains("cua_node")
    }
}

private struct ProcessRecord {
    let processID: Int
    let parentProcessID: Int
    let shortName: String
    let executablePath: String
}
