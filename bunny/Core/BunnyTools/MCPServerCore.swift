import Foundation

/// A minimal HTTP request, as delivered to `MCPServerCore` by the transport layer.
/// Header names are lowercased by the caller.
struct HTTPRequestLite {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data
}

/// A minimal HTTP response, as produced by `MCPServerCore`.
struct HTTPResponseLite: Equatable {
    var status: Int
    var headers: [String: String]
    var body: Data
}

/// A new task to create, as parsed from `create_task` / `create_tasks` tool arguments.
struct NewTask: Equatable {
    var title: String
    var description: String?
    var timerMinutes: Double?
    var subtasks: [String]
}

/// The Bunny tools an agent can invoke, already validated.
enum BunnyToolCall: Equatable {
    case listTasks(includeCompleted: Bool)
    case createTask(NewTask, parentID: UUID?)
    case createTasks([NewTask], parentID: UUID?)
    case updateTask(id: UUID, title: String?, description: String?, timerMinutes: Double?)
    case completeTask(id: UUID, completed: Bool)
    case addToShelf(taskID: UUID, paths: [String])
}

/// An error surfaced from argument parsing or from the backend, reported to the agent
/// as a tool-result error (`isError: true`), not a JSON-RPC error.
struct BunnyToolError: Error, Equatable {
    var message: String
}

/// Executes a validated `BunnyToolCall` against Bunny's task store. Implemented by the app;
/// tests use a fake. `perform` is expected to run on the main actor when compiled into the app
/// target (default MainActor isolation), since it touches SwiftData.
protocol BunnyToolsBackend: AnyObject {
    /// - Returns: `.success(json)` with the tool result encoded as a JSON text string, or
    ///   `.failure` with a message to report back to the agent.
    func perform(_ call: BunnyToolCall, contextTaskID: UUID?) -> Result<String, BunnyToolError>
}

/// Core protocol handling for Bunny's local MCP server: JSON-RPC over a single `POST /mcp`
/// endpoint (MCP "Streamable HTTP" transport, minimal/non-streaming variant — every response is
/// a single `application/json` body, never SSE). Holds no global mutable state; safe to
/// instantiate on any actor, and `handle` is synchronous so it can be called directly from the
/// main actor by the app.
final class MCPServerCore {
    private static let supportedProtocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
    private static let defaultProtocolVersion = "2025-06-18"
    private static let serverVersion = "1.0"

    private let token: String
    private let backend: BunnyToolsBackend

    init(token: String, backend: BunnyToolsBackend) {
        self.token = token
        self.backend = backend
    }

    func handle(_ request: HTTPRequestLite) -> HTTPResponseLite {
        guard request.path == "/mcp" else {
            return HTTPResponseLite(status: 404, headers: [:], body: Data())
        }
        guard request.method == "POST" else {
            return HTTPResponseLite(status: 405, headers: [:], body: Data())
        }
        guard isAuthorized(request) else {
            return HTTPResponseLite(status: 401, headers: [:], body: Data())
        }

        guard
            let object = try? JSONSerialization.jsonObject(with: request.body),
            let message = object as? [String: Any]
        else {
            return jsonResponse(status: 200, body: errorEnvelope(id: nil, code: -32700, message: "Parse error"))
        }

        let id = message["id"]
        let hasID = message.keys.contains("id")
        let method = message["method"] as? String
        let params = message["params"] as? [String: Any] ?? [:]

        guard let method else {
            // A JSON-RPC response (result/error, no method) sent by the client: nothing to reply.
            return HTTPResponseLite(status: 202, headers: [:], body: Data())
        }

        if !hasID || method.hasPrefix("notifications/") {
            return HTTPResponseLite(status: 202, headers: [:], body: Data())
        }

        switch method {
        case "initialize":
            return jsonResponse(status: 200, body: initializeResult(id: id, params: params))
        case "ping":
            return jsonResponse(status: 200, body: successEnvelope(id: id, result: [:]))
        case "tools/list":
            return jsonResponse(status: 200, body: successEnvelope(id: id, result: ["tools": BunnyToolsSchema.tools]))
        case "tools/call":
            return jsonResponse(status: 200, body: toolCallResult(id: id, params: params, request: request))
        default:
            return jsonResponse(status: 200, body: errorEnvelope(id: id, code: -32601, message: "Method not found"))
        }
    }

    // MARK: - Auth

    private func isAuthorized(_ request: HTTPRequestLite) -> Bool {
        guard let authHeader = request.headers["authorization"] else { return false }
        let prefix = "Bearer "
        guard authHeader.hasPrefix(prefix) else { return false }
        let provided = String(authHeader.dropFirst(prefix.count))
        return Self.constantTimeEquals(provided, token)
    }

    private static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        var diff: UInt8 = aBytes.count == bBytes.count ? 0 : 1
        let count = max(aBytes.count, bBytes.count)
        for i in 0..<count {
            let x = i < aBytes.count ? aBytes[i] : 0
            let y = i < bBytes.count ? bBytes[i] : 0
            diff |= x ^ y
        }
        return diff == 0
    }

    // MARK: - Methods

    private func initializeResult(id: Any?, params: [String: Any]) -> [String: Any] {
        let clientVersion = params["protocolVersion"] as? String
        let protocolVersion: String
        if let clientVersion, Self.supportedProtocolVersions.contains(clientVersion) {
            protocolVersion = clientVersion
        } else {
            protocolVersion = Self.defaultProtocolVersion
        }
        let result: [String: Any] = [
            "protocolVersion": protocolVersion,
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": ["name": "bunny", "version": Self.serverVersion],
        ]
        return successEnvelope(id: id, result: result)
    }

    private func toolCallResult(id: Any?, params: [String: Any], request: HTTPRequestLite) -> [String: Any] {
        guard let name = params["name"] as? String else {
            return errorEnvelope(id: id, code: -32602, message: "Invalid params")
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        let contextTaskID = request.headers["x-bunny-task"].flatMap { UUID(uuidString: $0) }

        switch BunnyToolArguments.parse(name: name, arguments: arguments) {
        case .failure(let error):
            return successEnvelope(id: id, result: toolResultPayload(text: error.message, isError: true))
        case .success(let call):
            switch backend.perform(call, contextTaskID: contextTaskID) {
            case .success(let text):
                return successEnvelope(id: id, result: toolResultPayload(text: text, isError: false))
            case .failure(let error):
                return successEnvelope(id: id, result: toolResultPayload(text: error.message, isError: true))
            }
        }
    }

    private func toolResultPayload(text: String, isError: Bool) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": isError]
    }

    // MARK: - Envelopes

    private func successEnvelope(id: Any?, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
    }

    private func errorEnvelope(id: Any?, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }

    private func jsonResponse(status: Int, body: [String: Any]) -> HTTPResponseLite {
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        return HTTPResponseLite(status: status, headers: ["Content-Type": "application/json"], body: data)
    }
}
