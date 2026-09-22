import Foundation
import Network

final class LocalResponseProxy: @unchecked Sendable {
    typealias StateHandler = @Sendable (ProxyRuntimeState) -> Void
    typealias ObservationHandler = @Sendable (ProxyObservation) -> Void

    private let queue = DispatchQueue(label: "app.modelsentinel.proxy", qos: .userInitiated)
    private var listener: NWListener?
    private var connections: [UUID: ProxyConnection] = [:]

    func start(
        port: UInt16,
        upstreamBaseURL: URL,
        onState: @escaping StateHandler,
        onObservation: @escaping ObservationHandler
    ) throws {
        stop()

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: port)!
        )
        let listener = try NWListener(using: parameters)
        self.listener = listener

        listener.stateUpdateHandler = { state in
            switch state {
            case .setup, .waiting:
                onState(.starting)
            case .ready:
                onState(.running)
            case .failed(let error):
                onState(.failed(error.localizedDescription))
            case .cancelled:
                onState(.stopped)
            @unknown default:
                break
            }
        }
        listener.newConnectionHandler = { connection in
            let id = UUID()
            let handler = ProxyConnection(
                connection: connection,
                upstreamBaseURL: upstreamBaseURL,
                queue: self.queue,
                onObservation: onObservation,
                onFinish: { [weak self] in
                    self?.removeConnection(id)
                }
            )
            self.connections[id] = handler
            handler.start()
        }
        onState(.starting)
        listener.start(queue: queue)
    }

    func stop() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        queue.sync {
            self.connections.values.forEach { $0.cancel() }
            self.connections.removeAll()
        }
    }

    private func removeConnection(_ id: UUID) {
        queue.async { [weak self] in
            self?.connections.removeValue(forKey: id)
        }
    }
}

private final class ProxyConnection: @unchecked Sendable {
    private struct IncomingRequest {
        let method: String
        let target: String
        let headers: [(String, String)]
        let body: Data

        func header(named name: String) -> String? {
            headers.first { $0.0.caseInsensitiveCompare(name) == .orderedSame }?.1
        }
    }

    private let connection: NWConnection
    private let upstreamBaseURL: URL
    private let queue: DispatchQueue
    private let onObservation: LocalResponseProxy.ObservationHandler
    private let onFinish: @Sendable () -> Void
    private let finishLock = NSLock()
    private var received = Data()
    private var hasStartedForwarding = false
    private var hasFinished = false

    init(
        connection: NWConnection,
        upstreamBaseURL: URL,
        queue: DispatchQueue,
        onObservation: @escaping LocalResponseProxy.ObservationHandler,
        onFinish: @escaping @Sendable () -> Void
    ) {
        self.connection = connection
        self.upstreamBaseURL = upstreamBaseURL
        self.queue = queue
        self.onObservation = onObservation
        self.onFinish = onFinish
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                self?.finish()
            }
        }
        connection.start(queue: queue)
        receiveRequest()
    }

    func cancel() {
        finish()
    }

    private func receiveRequest() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data { received.append(data) }
            if let request = parseRequest(), !hasStartedForwarding {
                hasStartedForwarding = true
                Task { await forward(request) }
                return
            }
            if error != nil || isComplete {
                sendError(status: 400, message: "Incomplete HTTP request")
                return
            }
            receiveRequest()
        }
    }

    private func parseRequest() -> IncomingRequest? {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let headerRange = received.range(of: delimiter),
              let headerText = String(data: received[..<headerRange.lowerBound], encoding: .utf8) else {
            return nil
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count == 3 else { return nil }

        let headers: [(String, String)] = lines.dropFirst().compactMap { line in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            return (name, value)
        }
        let contentLength = headers.first {
            $0.0.caseInsensitiveCompare("Content-Length") == .orderedSame
        }.flatMap { Int($0.1) } ?? 0
        let bodyStart = headerRange.upperBound
        guard received.count >= bodyStart + contentLength else { return nil }
        let body = received.subdata(in: bodyStart..<(bodyStart + contentLength))
        return IncomingRequest(
            method: requestParts[0],
            target: requestParts[1],
            headers: headers,
            body: body
        )
    }

    private func forward(_ request: IncomingRequest) async {
        let startedAt = ContinuousClock.now
        guard let targetURL = upstreamURL(for: request.target) else {
            sendError(status: 502, message: "Invalid upstream URL")
            return
        }

        var upstreamRequest = URLRequest(url: targetURL)
        upstreamRequest.httpMethod = request.method
        upstreamRequest.httpBody = request.body.isEmpty ? nil : request.body
        for (name, value) in request.headers where !Self.hopByHopHeaders.contains(name.lowercased()) {
            upstreamRequest.setValue(value, forHTTPHeaderField: name)
        }
        upstreamRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

        let requestedModelID = Self.modelID(in: request.body)
        let inspector = ResponseInspector()

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: upstreamRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            try await sendResponseHead(httpResponse)

            var chunk = Data()
            chunk.reserveCapacity(8 * 1024)
            for try await byte in bytes {
                chunk.append(byte)
                if chunk.count >= 8 * 1024 {
                    inspector.consume(chunk)
                    try await sendChunk(chunk)
                    chunk.removeAll(keepingCapacity: true)
                }
            }
            if !chunk.isEmpty {
                inspector.consume(chunk)
                try await sendChunk(chunk)
            }
            inspector.finish()
            try await sendRaw(Data("0\r\n\r\n".utf8))
            finish()

            let duration = startedAt.duration(to: .now)
            let latencyMS = Int(duration.components.seconds * 1_000) +
                Int(duration.components.attoseconds / 1_000_000_000_000_000)
            onObservation(
                ProxyObservation(
                    requestedModelID: requestedModelID,
                    responseModelID: inspector.modelID,
                    responseID: inspector.responseID,
                    upstreamHost: targetURL.host ?? upstreamBaseURL.host ?? "未知",
                    latencyMS: latencyMS,
                    observedAt: .now
                )
            )
        } catch {
            sendError(status: 502, message: "Upstream request failed")
        }
    }

    private func upstreamURL(for target: String) -> URL? {
        guard let targetComponents = URLComponents(string: target),
              let targetPath = targetComponents.path.removingPercentEncoding else {
            return nil
        }
        var components = URLComponents(url: upstreamBaseURL, resolvingAgainstBaseURL: false)
        let basePath = components?.path ?? ""
        if !basePath.isEmpty, basePath != "/", targetPath.hasPrefix(basePath) {
            components?.path = targetPath
        } else {
            components?.path = Self.joinPath(basePath, targetPath)
        }
        components?.percentEncodedQuery = targetComponents.percentEncodedQuery
        return components?.url
    }

    private func sendResponseHead(_ response: HTTPURLResponse) async throws {
        var lines = ["HTTP/1.1 \(response.statusCode) \(Self.reasonPhrase(for: response.statusCode))"]
        for (rawName, rawValue) in response.allHeaderFields {
            guard let name = rawName as? String,
                  !Self.hopByHopHeaders.contains(name.lowercased()),
                  name.caseInsensitiveCompare("Content-Encoding") != .orderedSame else { continue }
            lines.append("\(name): \(rawValue)")
        }
        lines.append("Transfer-Encoding: chunked")
        lines.append("Connection: close")
        lines.append("")
        lines.append("")
        try await sendRaw(Data(lines.joined(separator: "\r\n").utf8))
    }

    private func sendChunk(_ data: Data) async throws {
        var framed = Data(String(data.count, radix: 16).utf8)
        framed.append(Data("\r\n".utf8))
        framed.append(data)
        framed.append(Data("\r\n".utf8))
        try await sendRaw(framed)
    }

    private func sendRaw(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func sendError(status: Int, message: String) {
        let body = Data("{\"error\":\"\(message)\"}".utf8)
        let head = "HTTP/1.1 \(status) \(Self.reasonPhrase(for: status))\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var response = Data(head.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            self?.finish()
        })
    }

    private func finish() {
        finishLock.lock()
        guard !hasFinished else {
            finishLock.unlock()
            return
        }
        hasFinished = true
        finishLock.unlock()
        connection.cancel()
        onFinish()
    }

    private static func modelID(in body: Data) -> String? {
        guard !body.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        return object["model"] as? String
    }

    private static func joinPath(_ base: String, _ target: String) -> String {
        let left = base.hasSuffix("/") ? String(base.dropLast()) : base
        let right = target.hasPrefix("/") ? target : "/\(target)"
        return left + right
    }

    private static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 201: "Created"
        case 204: "No Content"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 429: "Too Many Requests"
        case 500: "Internal Server Error"
        case 502: "Bad Gateway"
        case 503: "Service Unavailable"
        default: "HTTP Response"
        }
    }

    private static let hopByHopHeaders: Set<String> = [
        "connection", "content-length", "host", "keep-alive", "proxy-authenticate",
        "proxy-authorization", "te", "trailer", "transfer-encoding", "upgrade"
    ]
}

private final class ResponseInspector: @unchecked Sendable {
    private let maximumInspectionBytes = 2 * 1024 * 1024
    private var buffer = Data()
    private(set) var modelID: String?
    private(set) var responseID: String?

    func consume(_ data: Data) {
        guard buffer.count < maximumInspectionBytes else { return }
        buffer.append(data.prefix(maximumInspectionBytes - buffer.count))
        inspectEventLines()
    }

    func finish() {
        inspectJSON(buffer)
    }

    private func inspectEventLines() {
        guard let text = String(data: buffer, encoding: .utf8) else { return }
        for line in text.split(whereSeparator: \.isNewline) {
            let raw = line.hasPrefix("data:")
                ? line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                : String(line)
            guard raw != "[DONE]", let data = raw.data(using: .utf8) else { continue }
            inspectJSON(data)
        }
    }

    private func inspectJSON(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        if let model = object["model"] as? String { modelID = model }
        if let id = object["id"] as? String { responseID = id }
        if let response = object["response"] as? [String: Any] {
            if let model = response["model"] as? String { modelID = model }
            if let id = response["id"] as? String { responseID = id }
        }
    }
}
