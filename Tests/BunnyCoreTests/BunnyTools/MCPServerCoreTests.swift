import Foundation
import Testing
@testable import BunnyCore

private final class FakeBunnyToolsBackend: BunnyToolsBackend {
    var result: Result<String, BunnyToolError> = .success(#"{"ok":true}"#)
    var lastCall: BunnyToolCall?
    var lastContextTaskID: UUID?
    var callCount = 0

    func perform(_ call: BunnyToolCall, contextTaskID: UUID?) -> Result<String, BunnyToolError> {
        callCount += 1
        lastCall = call
        lastContextTaskID = contextTaskID
        return result
    }
}

struct MCPServerCoreTests {
    let token = "s3cr3t-token-value"

    func makeRequest(
        method: String = "POST",
        path: String = "/mcp",
        body: [String: Any]? = nil,
        rawBody: Data? = nil,
        token overrideToken: String? = nil,
        includeAuth: Bool = true,
        extraHeaders: [String: String] = [:]
    ) -> HTTPRequestLite {
        var headers = extraHeaders
        if includeAuth {
            headers["authorization"] = "Bearer \(overrideToken ?? token)"
        }
        let data: Data
        if let rawBody {
            data = rawBody
        } else if let body {
            data = try! JSONSerialization.data(withJSONObject: body)
        } else {
            data = Data()
        }
        return HTTPRequestLite(method: method, path: path, headers: headers, body: data)
    }

    func decodeJSON(_ response: HTTPResponseLite) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: response.body) as? [String: Any]) ?? [:]
    }

    // MARK: - Routing

    @Test func getOnMCPReturns405() {
        let server = MCPServerCore(token: token, backend: FakeBunnyToolsBackend())
        let response = server.handle(makeRequest(method: "GET", body: [:]))
        #expect(response.status == 405)
    }

    @Test func unknownPathReturns404() {
        let server = MCPServerCore(token: token, backend: FakeBunnyToolsBackend())
        let response = server.handle(makeRequest(path: "/other", body: [:]))
        #expect(response.status == 404)
    }

    @Test func unknownPathWithGETReturns404() {
        let server = MCPServerCore(token: token, backend: FakeBunnyToolsBackend())
        let response = server.handle(makeRequest(method: "GET", path: "/other", body: [:]))
        #expect(response.status == 404)
    }

    // MARK: - Auth

    @Test func missingTokenReturns401() {
        let backend = FakeBunnyToolsBackend()
        let server = MCPServerCore(token: token, backend: backend)
        let response = server.handle(makeRequest(body: initializeBody(), includeAuth: false))
        #expect(response.status == 401)
        #expect(backend.callCount == 0)
    }

    @Test func wrongTokenReturns401() {
        let backend = FakeBunnyToolsBackend()
        let server = MCPServerCore(token: token, backend: backend)
        let response = server.handle(makeRequest(body: initializeBody(), token: "wrong-token"))
        #expect(response.status == 401)
        #expect(backend.callCount == 0)
    }

    @Test func unauthorizedRequestNeverTouchesBackend() {
        let backend = FakeBunnyToolsBackend()
        let server = MCPServerCore(token: token, backend: backend)
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": ["name": "list_tasks", "arguments": [:]],
        ]
        _ = server.handle(makeRequest(body: body, includeAuth: false))
        #expect(backend.callCount == 0)
    }

    // MARK: - initialize

    @Test func initializeReturnsServerInfoAndCapabilities() {
        let server = MCPServerCore(token: token, backend: FakeBunnyToolsBackend())
        let response = server.handle(makeRequest(body: initializeBody()))
        #expect(response.status == 200)
        let json = decodeJSON(response)
        let result = json["result"] as? [String: Any]
        let serverInfo = result?["serverInfo"] as? [String: Any]
        let capabilities = result?["capabilities"] as? [String: Any]
        #expect(serverInfo?["name"] as? String == "bunny")
        #expect(capabilities?["tools"] != nil)
    }

    @Test func initializeEchoesSupportedProtocolVersion() {
        let server = MCPServerCore(token: token, backend: FakeBunnyToolsBackend())
        let response = server.handle(makeRequest(body: initializeBody(protocolVersion: "2024-11-05")))
        let json = decodeJSON(response)
        let result = json["result"] as? [String: Any]
        #expect(result?["protocolVersion"] as? String == "2024-11-05")
    }

    @Test func initializeFallsBackForUnsupportedProtocolVersion() {
        let server = MCPServerCore(token: token, backend: FakeBunnyToolsBackend())
        let response = server.handle(makeRequest(body: initializeBody(protocolVersion: "1999-01-01")))
        let json = decodeJSON(response)
        let result = json["result"] as? [String: Any]
        #expect(result?["protocolVersion"] as? String == "2025-06-18")
    }

    /// Claude Code 2.1.281 requests `protocolVersion: "2025-11-25"` (newer than our allow-list,
    /// per docs/superpowers/research/mcp-http.md §1) — it must fall back, not be hard-rejected.
    @Test func initializeFallsBackForClaudeCodesNewerProtocolVersion() {
        let server = MCPServerCore(token: token, backend: FakeBunnyToolsBackend())
        let response = server.handle(makeRequest(body: initializeBody(protocolVersion: "2025-11-25")))
        #expect(response.status == 200)
        let json = decodeJSON(response)
        let result = json["result"] as? [String: Any]
        #expect(result?["protocolVersion"] as? String == "2025-06-18")
    }

    // MARK: - ping

    @Test func pingReturnsEmptyResult() {
        let server = MCPServerCore(token: token, backend: FakeBunnyToolsBackend())
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 5, "method": "ping"]
        let response = server.handle(makeRequest(body: body))
        let json = decodeJSON(response)
        #expect(json["id"] as? Int == 5)
        #expect(json["result"] as? [String: String] == [:])
    }

    // MARK: - tools/list

    @Test func toolsListReturnsAllToolNames() {
        let server = MCPServerCore(token: token, backend: FakeBunnyToolsBackend())
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "tools/list"]
        let response = server.handle(makeRequest(body: body))
        let json = decodeJSON(response)
        let result = json["result"] as? [String: Any]
        let tools = result?["tools"] as? [[String: Any]] ?? []
        let names = Set(tools.compactMap { $0["name"] as? String })
        #expect(names == ["list_tasks", "create_task", "create_tasks", "update_task", "complete_task", "add_to_shelf"])
    }

    // MARK: - notifications

    @Test func notificationReturns202WithEmptyBody() {
        let server = MCPServerCore(token: token, backend: FakeBunnyToolsBackend())
        let body: [String: Any] = ["jsonrpc": "2.0", "method": "notifications/initialized"]
        let response = server.handle(makeRequest(body: body))
        #expect(response.status == 202)
        #expect(response.body.isEmpty)
    }

    // MARK: - errors

    @Test func unknownMethodReturnsMethodNotFound() {
        let server = MCPServerCore(token: token, backend: FakeBunnyToolsBackend())
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 9, "method": "bogus/method"]
        let response = server.handle(makeRequest(body: body))
        let json = decodeJSON(response)
        let error = json["error"] as? [String: Any]
        #expect(error?["code"] as? Int == -32601)
        #expect(json["id"] as? Int == 9)
    }

    @Test func malformedJSONReturns400WithParseError() {
        let server = MCPServerCore(token: token, backend: FakeBunnyToolsBackend())
        let response = server.handle(makeRequest(rawBody: Data("{not json".utf8)))
        #expect(response.status == 400)
        let json = decodeJSON(response)
        let error = json["error"] as? [String: Any]
        #expect(error?["code"] as? Int == -32700)
    }

    @Test func topLevelArrayBatchReturns400WithInvalidRequest() {
        let server = MCPServerCore(token: token, backend: FakeBunnyToolsBackend())
        let response = server.handle(makeRequest(rawBody: Data("[]".utf8)))
        #expect(response.status == 400)
        let json = decodeJSON(response)
        let error = json["error"] as? [String: Any]
        #expect(error?["code"] as? Int == -32600)
        #expect(error?["message"] as? String == "batch requests are not supported")
    }

    @Test func nonObjectJSONReturns400WithParseError() {
        let server = MCPServerCore(token: token, backend: FakeBunnyToolsBackend())
        let response = server.handle(makeRequest(rawBody: Data("42".utf8)))
        #expect(response.status == 400)
        let json = decodeJSON(response)
        let error = json["error"] as? [String: Any]
        #expect(error?["code"] as? Int == -32700)
    }

    // MARK: - tools/call

    @Test func toolsCallSuccessReturnsBackendResultAsText() {
        let backend = FakeBunnyToolsBackend()
        backend.result = .success(#"{"id":"abc"}"#)
        let server = MCPServerCore(token: token, backend: backend)
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/call",
            "params": ["name": "list_tasks", "arguments": ["include_completed": false]],
        ]
        let response = server.handle(makeRequest(body: body))
        let json = decodeJSON(response)
        let result = json["result"] as? [String: Any]
        let content = result?["content"] as? [[String: Any]]
        #expect(content?.first?["text"] as? String == #"{"id":"abc"}"#)
        #expect(result?["isError"] as? Bool == false)
        #expect(backend.lastCall == .listTasks(includeCompleted: false))
    }

    @Test func toolsCallBackendErrorReturnsIsErrorTrue() {
        let backend = FakeBunnyToolsBackend()
        backend.result = .failure(BunnyToolError(message: "task not found"))
        let server = MCPServerCore(token: token, backend: backend)
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": ["name": "complete_task", "arguments": ["id": UUID().uuidString]],
        ]
        let response = server.handle(makeRequest(body: body))
        let json = decodeJSON(response)
        let result = json["result"] as? [String: Any]
        let content = result?["content"] as? [[String: Any]]
        #expect(result?["isError"] as? Bool == true)
        #expect(content?.first?["text"] as? String == "task not found")
    }

    @Test func toolsCallInvalidArgumentsReturnsIsErrorWithoutCallingBackend() {
        let backend = FakeBunnyToolsBackend()
        let server = MCPServerCore(token: token, backend: backend)
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 4,
            "method": "tools/call",
            "params": ["name": "create_task", "arguments": [:]],
        ]
        let response = server.handle(makeRequest(body: body))
        let json = decodeJSON(response)
        let result = json["result"] as? [String: Any]
        #expect(result?["isError"] as? Bool == true)
        #expect(backend.callCount == 0)
    }

    // MARK: - context header

    @Test func contextHeaderBecomesContextTaskID() {
        let backend = FakeBunnyToolsBackend()
        let server = MCPServerCore(token: token, backend: backend)
        let taskID = UUID()
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 6,
            "method": "tools/call",
            "params": ["name": "list_tasks", "arguments": [:]],
        ]
        _ = server.handle(makeRequest(body: body, extraHeaders: ["x-bunny-task": taskID.uuidString]))
        #expect(backend.lastContextTaskID == taskID)
    }

    @Test func missingContextHeaderYieldsNilContextTaskID() {
        let backend = FakeBunnyToolsBackend()
        let server = MCPServerCore(token: token, backend: backend)
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 7,
            "method": "tools/call",
            "params": ["name": "list_tasks", "arguments": [:]],
        ]
        _ = server.handle(makeRequest(body: body))
        #expect(backend.lastContextTaskID == nil)
    }
}

private func initializeBody(protocolVersion: String = "2025-06-18") -> [String: Any] {
    [
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": [
            "protocolVersion": protocolVersion,
            "capabilities": [:],
            "clientInfo": ["name": "test-client", "version": "1.0"],
        ],
    ]
}
