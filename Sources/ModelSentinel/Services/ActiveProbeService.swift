import Foundation

actor ActiveProbeService {
    static let shared = ActiveProbeService()

    enum ProbeError: LocalizedError {
        case codexNotFound
        case launchFailed(String)
        case nonzeroExit(Int32)
        case noResult
        case timedOut

        var errorDescription: String? {
            switch self {
            case .codexNotFound: "未找到 Codex CLI"
            case .launchFailed(let message): "无法启动 Codex：\(message)"
            case .nonzeroExit(let code): "Codex 探针退出码 \(code)"
            case .noResult: "未取得可解析的探针结果"
            case .timedOut: "主动探针超过两分钟"
            }
        }
    }

    func run(modelID: String?) async throws -> ActiveProbeResult {
        let executable = try Self.codexExecutable()
        let startedAt = ContinuousClock.now
        let output = try await Self.runProcess(executable: executable, modelID: modelID)

        let checks = [
            output.contains("A=1369"),
            output.contains("B=10"),
            output.contains("C=K7M2")
        ]
        guard checks.contains(true) else { throw ProbeError.noResult }

        let duration = startedAt.duration(to: .now)
        let durationMS = Int(duration.components.seconds * 1_000) +
            Int(duration.components.attoseconds / 1_000_000_000_000_000)
        return ActiveProbeResult(
            modelID: modelID,
            passedChecks: checks.filter { $0 }.count,
            totalChecks: checks.count,
            durationMS: durationMS,
            completedAt: .now
        )
    }

    private static func codexExecutable() throws -> URL {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        guard let path = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw ProbeError.codexNotFound
        }
        return URL(fileURLWithPath: path)
    }

    private static func runProcess(executable: URL, modelID: String?) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let outputPipe = Pipe()
            process.executableURL = executable

            var arguments = [
                "exec",
                "--ephemeral",
                "--json",
                "--sandbox", "read-only",
                "--skip-git-repo-check",
                "--ignore-rules"
            ]
            if let modelID, !modelID.isEmpty {
                arguments.append(contentsOf: ["--model", modelID])
            }
            arguments.append(Self.prompt)
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            process.currentDirectoryURL = FileManager.default.temporaryDirectory

            do {
                try process.run()
            } catch {
                throw ProbeError.launchFailed(error.localizedDescription)
            }

            let deadline = Date().addingTimeInterval(120)
            while process.isRunning, Date() < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            let timedOut = process.isRunning
            if timedOut { process.terminate() }
            process.waitUntilExit()
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            if timedOut { throw ProbeError.timedOut }
            guard process.terminationStatus == 0 else {
                throw ProbeError.nonzeroExit(process.terminationStatus)
            }
            return String(data: outputData, encoding: .utf8) ?? ""
        }.value
    }

    private static let prompt = """
    This is a synthetic ModelSentinel capability check. Do not use tools, inspect files, or access the network. Solve the three tasks and include exactly one marker in the final answer using this format: MS_PROBE_V1|A=<answer>|B=<answer>|C=<answer>

    A: Compute 37 × 37.
    B: Evaluate [1, 2, 3].map(x => x * 2).filter(x => x > 2).reduce((a, b) => a + b, 0).
    C: Copy the token K7M2 exactly.
    """
}
