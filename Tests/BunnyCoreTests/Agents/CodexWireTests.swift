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
