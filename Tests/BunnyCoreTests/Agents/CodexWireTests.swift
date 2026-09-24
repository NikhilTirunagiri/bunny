import Foundation
import Testing
@testable import BunnyCore

struct CodexWireTests {
    @Test func parsesBasicFixture() throws {
        let incoming = try fixture("codex-basic.jsonl").map(CodexWire.parse)

        let threadResponse = incoming.contains { value in
            guard case let .response(id, threadID, turnID, error) = value else { return false }
            return id == 2 && threadID != nil && turnID == nil && error == nil
        }
        let hasDelta = incoming.contains { value in
            if case .agentMessageDelta = value { return true }
            return false
        }

        #expect(threadResponse)
        #expect(hasDelta)
        #expect(incoming.contains(.agentMessage("OK")))
        #expect(incoming.last == .turnCompleted(turnID: "01a0d1be-9289-7d90-a540-f5121a030b9b", status: "completed", error: nil))
    }

    @Test func parsesUnsupportedRequestFromRun3Fixture() throws {
        let incoming = try fixture("codex-run3.jsonl").map(CodexWire.parse)
        #expect(incoming.contains(.unsupportedRequest(rpcID: "0")))
    }

    @Test func parsesTurnCommandCompletionAndApprovals() {
        let turnStarted = Data(#"{"jsonrpc":"2.0","method":"turn/started","params":{"turn":{"id":"turn-1"}}}"#.utf8)
        let commandStarted = Data(#"{"jsonrpc":"2.0","method":"item/started","params":{"item":{"type":"commandExecution","command":"git status"}}}"#.utf8)
        let commandApproval = Data(#"{"jsonrpc":"2.0","id":7,"method":"item/commandExecution/requestApproval","params":{"command":"git status"}}"#.utf8)
        let fileApproval = Data(#"{"jsonrpc":"2.0","id":"edit-1","method":"item/fileChange/requestApproval","params":{"reason":"Update source"}}"#.utf8)
        let failed = Data(#"{"jsonrpc":"2.0","method":"turn/completed","params":{"turn":{"id":"turn-1","status":"failed","error":{"message":"boom"}}}}"#.utf8)

        #expect(CodexWire.parse(turnStarted) == .turnStarted(turnID: "turn-1"))
        #expect(CodexWire.parse(commandStarted) == .commandStarted("git status"))
        #expect(CodexWire.parse(commandApproval) == .approvalRequest(rpcID: "7", method: "item/commandExecution/requestApproval", title: "Run command", detail: "git status"))
        #expect(CodexWire.parse(fileApproval) == .approvalRequest(rpcID: "edit-1", method: "item/fileChange/requestApproval", title: "Edit files", detail: "Update source"))
        #expect(CodexWire.parse(failed) == .turnCompleted(turnID: "turn-1", status: "failed", error: "boom"))
    }

    @Test func parsesResponsesAndIgnoresMalformedJSON() {
        let turn = Data(#"{"jsonrpc":"2.0","id":3,"result":{"turn":{"id":"turn-1"}}}"#.utf8)
        let error = Data(#"{"jsonrpc":"2.0","id":4,"error":{"message":"bad request"}}"#.utf8)

        #expect(CodexWire.parse(turn) == .response(id: 3, threadID: nil, turnID: "turn-1", error: nil))
        #expect(CodexWire.parse(error) == .response(id: 4, threadID: nil, turnID: nil, error: "bad request"))
        #expect(CodexWire.parse(Data("garbage".utf8)) == .ignored)
    }

    @Test func approvalReplyPreservesNumericRPCID() throws {
        let object = try jsonObject(CodexWire.approvalReply(rpcID: "7", approved: true))
        let result = try #require(object["result"] as? [String: Any])

        #expect(object["jsonrpc"] as? String == "2.0")
        #expect(object["id"] as? Int == 7)
        #expect(result["decision"] as? String == "accept")
    }

    @Test func threadStartWithoutRootsOmitsConfig() throws {
        let object = try jsonObject(CodexWire.threadStart(
            id: 2,
            cwd: "/tmp/project",
            approvalPolicy: "never",
            sandbox: "workspace-write",
            developerInstructions: "Be concise",
            writableRoots: []
        ))
        let params = try #require(object["params"] as? [String: Any])

        #expect(object["method"] as? String == "thread/start")
        #expect(params["cwd"] as? String == "/tmp/project")
        #expect(params["approvalPolicy"] as? String == "never")
        #expect(params["sandbox"] as? String == "workspace-write")
        #expect(params["developerInstructions"] as? String == "Be concise")
        #expect(params["config"] == nil)
    }

    @Test func threadStartWithRootsNestsConfig() throws {
        let object = try jsonObject(CodexWire.threadStart(
            id: 2,
            cwd: "/tmp/project",
            approvalPolicy: "never",
            sandbox: "workspace-write",
            developerInstructions: "Be concise",
            writableRoots: ["/tmp/shared"]
        ))
        let params = try #require(object["params"] as? [String: Any])
        let config = try #require(params["config"] as? [String: Any])
        let workspaceWrite = try #require(config["sandbox_workspace_write"] as? [String: Any])

        #expect(workspaceWrite["writable_roots"] as? [String] == ["/tmp/shared"])
    }

    @Test func encodesHandshakeTurnsAndErrors() throws {
        let initialize = try jsonObject(CodexWire.initialize(id: 1))
        let initializeParams = try #require(initialize["params"] as? [String: Any])
        let clientInfo = try #require(initializeParams["clientInfo"] as? [String: Any])
        let capabilities = try #require(initializeParams["capabilities"] as? [String: Any])
        #expect(initialize["jsonrpc"] as? String == "2.0")
        #expect(initialize["method"] as? String == "initialize")
        #expect(clientInfo["name"] as? String == "bunny")
        #expect(clientInfo["version"] as? String == "1.0")
        #expect(capabilities["experimentalApi"] as? Bool == true)

        let initialized = try jsonObject(CodexWire.initialized())
        #expect(initialized["method"] as? String == "initialized")
        #expect(initialized["id"] == nil)

        let resume = try jsonObject(CodexWire.threadResume(id: 3, threadID: "thread-1"))
        #expect((resume["params"] as? [String: Any])?["threadId"] as? String == "thread-1")

        let start = try jsonObject(CodexWire.turnStart(id: 4, threadID: "thread-1", text: "Hello"))
        let startParams = try #require(start["params"] as? [String: Any])
        let input = try #require(startParams["input"] as? [[String: Any]])
        #expect(start["method"] as? String == "turn/start")
        #expect(input.first?["type"] as? String == "text")
        #expect(input.first?["text"] as? String == "Hello")

        let interrupt = try jsonObject(CodexWire.turnInterrupt(id: 5, threadID: "thread-1", turnID: "turn-1"))
        let interruptParams = try #require(interrupt["params"] as? [String: Any])
        #expect(interruptParams["threadId"] as? String == "thread-1")
        #expect(interruptParams["turnId"] as? String == "turn-1")

        let declined = try jsonObject(CodexWire.approvalReply(rpcID: "request-1", approved: false))
        #expect(declined["id"] as? String == "request-1")
        #expect((declined["result"] as? [String: Any])?["decision"] as? String == "decline")

        let unsupported = try jsonObject(CodexWire.methodNotFound(rpcID: "request-2"))
        let rpcError = try #require(unsupported["error"] as? [String: Any])
        #expect(unsupported["id"] as? String == "request-2")
        #expect(rpcError["code"] as? Int == -32601)
        #expect(rpcError["message"] as? String == "unsupported")
    }

    private static let tools = BunnyToolsEndpoint(
        url: "http://127.0.0.1:47823/mcp",
        token: "secret-token",
        taskID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")
    )
    private static let expectedBunnyServer: NSDictionary = [
        "url": "http://127.0.0.1:47823/mcp",
        "http_headers": [
            "Authorization": "Bearer secret-token",
            "X-Bunny-Task": "11111111-2222-3333-4444-555555555555",
        ],
        "default_tools_approval_mode": "approve",
    ]

    @Test func threadStartWithModelToolsAndRootsMergesConfig() throws {
        let object = try jsonObject(CodexWire.threadStart(
            id: 2,
            cwd: "/tmp/project",
            approvalPolicy: "never",
            sandbox: "workspace-write",
            developerInstructions: "Be concise",
            writableRoots: ["/tmp/shared"],
            model: "gpt-6-luna",
            tools: Self.tools
        ))
        let params = try #require(object["params"] as? [String: Any])
        let config = try #require(params["config"] as? NSDictionary)
        let expectedConfig: NSDictionary = [
            "sandbox_workspace_write": ["writable_roots": ["/tmp/shared"]],
            "mcp_servers": ["bunny": Self.expectedBunnyServer],
        ]

        #expect(params["model"] as? String == "gpt-6-luna")
        #expect(params["approvalPolicy"] as? String == "never")
        #expect(params["sandbox"] as? String == "workspace-write")
        #expect(config == expectedConfig)
    }

    @Test func threadStartWithToolsOnlyHasOnlyMCPConfig() throws {
        let object = try jsonObject(CodexWire.threadStart(
            id: 2,
            cwd: "/tmp/project",
            approvalPolicy: "on-request",
            sandbox: "workspace-write",
            developerInstructions: "Be concise",
            writableRoots: [],
            model: " ",
            tools: Self.tools
        ))
        let params = try #require(object["params"] as? [String: Any])
        let config = try #require(params["config"] as? NSDictionary)
        let expectedConfig: NSDictionary = ["mcp_servers": ["bunny": Self.expectedBunnyServer]]

        #expect(params["model"] == nil)
        #expect(config == expectedConfig)
    }

    @Test func threadResumeCarriesModelAndTools() throws {
        let plain = try jsonObject(CodexWire.threadResume(id: 2, threadID: "th-1"))
        let plainParams = try #require(plain["params"] as? NSDictionary)
        let expectedPlain: NSDictionary = ["threadId": "th-1"]
        #expect(plainParams == expectedPlain)

        let full = try jsonObject(CodexWire.threadResume(id: 2, threadID: "th-1", model: "gpt-6-sol", tools: Self.tools))
        let fullParams = try #require(full["params"] as? NSDictionary)
        let expectedFull: NSDictionary = [
            "threadId": "th-1",
            "model": "gpt-6-sol",
            "config": ["mcp_servers": ["bunny": Self.expectedBunnyServer]],
        ]
        #expect(fullParams == expectedFull)
    }

    @Test func turnStartCarriesEffortWhenSet() throws {
        let withEffort = try jsonObject(CodexWire.turnStart(id: 4, threadID: "th-1", text: "Hi", effort: "high"))
        let withParams = try #require(withEffort["params"] as? [String: Any])
        #expect(withParams["effort"] as? String == "high")

        let blank = try jsonObject(CodexWire.turnStart(id: 4, threadID: "th-1", text: "Hi", effort: ""))
        let blankParams = try #require(blank["params"] as? [String: Any])
        #expect(blankParams["effort"] == nil)

        let none = try jsonObject(CodexWire.turnStart(id: 4, threadID: "th-1", text: "Hi"))
        let noneParams = try #require(none["params"] as? [String: Any])
        #expect(noneParams["effort"] == nil)
    }

    @Test func parsesMCPElicitationAndEncodesReply() throws {
        // Captured from codex-cli 0.155.0 (approvalPolicy "on-request", workspace-write) for a bunny tool call.
        let request = Data(#"{"method": "mcpServer/elicitation/request", "id": 0, "params": {"threadId": "t", "turnId": "u", "serverName": "bunny", "mode": "form", "_meta": {"codex_approval_kind": "mcp_tool_call", "persist": ["session", "always"], "tool_description": "Create a task in Bunny", "tool_params": {"title": "ProbeTask"}}, "message": "Allow the bunny MCP server to run tool \"create_task\"?", "requestedSchema": {"type": "object", "properties": {}}}}"#.utf8)
        #expect(CodexWire.parse(request) == .mcpElicitation(rpcID: "0", serverName: "bunny"))

        let accept = try jsonObject(CodexWire.elicitationReply(rpcID: "0", accept: true))
        let result = try #require(accept["result"] as? [String: Any])
        #expect(accept["id"] as? Int == 0)
        #expect(result["action"] as? String == "accept")
        #expect(result["content"] is NSNull)
        #expect(result["_meta"] is NSNull)

        let decline = try jsonObject(CodexWire.elicitationReply(rpcID: "e-1", accept: false))
        #expect(decline["id"] as? String == "e-1")
        #expect((decline["result"] as? [String: Any])?["action"] as? String == "decline")
    }

    @Test func encodesModelList() throws {
        let object = try jsonObject(CodexWire.modelList(id: 2))
        let params = try #require(object["params"] as? NSDictionary)
        let expected: NSDictionary = ["includeHidden": false]
        #expect(object["method"] as? String == "model/list")
        #expect(object["id"] as? Int == 2)
        #expect(params == expected)
    }

    @Test func parsesModelListFixture() throws {
        // Real `model/list` response from codex-cli 0.155.0, trimmed, plus one hidden entry.
        let line = try #require(try fixture("codex-model-list.json").first)
        let models = try #require(CodexWire.parseModelList(line))
        let expected = [
            CodexModel(id: "gpt-6-astra", displayName: "GPT-6-Astra", efforts: ["low", "medium", "high", "xhigh", "max", "ultra"], defaultEffort: "medium", isDefault: true),
            CodexModel(id: "gpt-6-sol", displayName: "GPT-6-Sol", efforts: ["low", "medium", "high", "xhigh", "max", "ultra"], defaultEffort: "medium", isDefault: false),
            CodexModel(id: "gpt-6-luna", displayName: "GPT-6-Luna", efforts: ["low", "medium", "high", "xhigh", "max"], defaultEffort: "medium", isDefault: false),
        ]
        #expect(models == expected)
    }

    @Test func parseModelListRejectsNonLists() {
        let error = Data(#"{"jsonrpc":"2.0","id":2,"error":{"code":-32000,"message":"nope"}}"#.utf8)
        let other = Data(#"{"jsonrpc":"2.0","id":2,"result":{"thread":{"id":"t"}}}"#.utf8)
        let empty = Data(#"{"id":2,"result":{"data":[],"nextCursor":null}}"#.utf8)
        #expect(CodexWire.parseModelList(error) == nil)
        #expect(CodexWire.parseModelList(other) == nil)
        #expect(CodexWire.parseModelList(Data("garbage".utf8)) == nil)
        #expect(CodexWire.parseModelList(empty) == [])
    }

    private func fixture(_ name: String) throws -> [Data] {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repositoryRoot
            .appendingPathComponent("docs/superpowers/research/fixtures")
            .appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        return [UInt8](data).split(separator: 0x0A).map { Data(Array($0)) }
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
