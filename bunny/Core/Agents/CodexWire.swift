import Foundation

enum CodexWire {
    enum Incoming: Equatable {
        case response(id: Int, threadID: String?, turnID: String?, error: String?)
        case turnStarted(turnID: String)
        case agentMessageDelta(String)
        case agentMessage(String)
        case commandStarted(String)
        case turnCompleted(turnID: String?, status: String, error: String?)
        case approvalRequest(rpcID: String, method: String, title: String, detail: String)
        /// `mcpServer/elicitation/request`: an MCP server (or Codex's own MCP tool-call approval) asks the user.
        case mcpElicitation(rpcID: String, serverName: String)
        case unsupportedRequest(rpcID: String)
        case ignored
    }

    static func parse(_ line: Data) -> Incoming {
        guard let object = jsonObject(line) else { return .ignored }

        if let method = object["method"] as? String {
            let params = object["params"] as? [String: Any] ?? [:]

            switch method {
            case "turn/started":
                guard let turn = params["turn"] as? [String: Any],
                      let turnID = turn["id"] as? String else {
                    return requestFallback(object)
                }
                return .turnStarted(turnID: turnID)

            case "item/agentMessage/delta":
                guard let delta = params["delta"] as? String else {
                    return requestFallback(object)
                }
                return .agentMessageDelta(delta)

            case "item/completed":
                guard let item = params["item"] as? [String: Any],
                      item["type"] as? String == "agentMessage",
                      let text = item["text"] as? String else {
                    return requestFallback(object)
                }
                return .agentMessage(text)

            case "item/started":
                guard let item = params["item"] as? [String: Any],
                      item["type"] as? String == "commandExecution",
                      let command = item["command"] as? String else {
                    return requestFallback(object)
                }
                return .commandStarted(command)

            case "turn/completed":
                guard let turn = params["turn"] as? [String: Any],
                      let status = turn["status"] as? String else {
                    return requestFallback(object)
                }
                let error = (turn["error"] as? [String: Any])?["message"] as? String
                return .turnCompleted(turnID: turn["id"] as? String, status: status, error: error)

            case "item/commandExecution/requestApproval":
                guard let rpcID = rpcIDString(object["id"]) else { return .ignored }
                return .approvalRequest(
                    rpcID: rpcID,
                    method: method,
                    title: "Run command",
                    detail: params["command"] as? String ?? ""
                )

            case "item/fileChange/requestApproval":
                guard let rpcID = rpcIDString(object["id"]) else { return .ignored }
                return .approvalRequest(
                    rpcID: rpcID,
                    method: method,
                    title: "Edit files",
                    detail: params["reason"] as? String ?? params["grantRoot"] as? String ?? ""
                )

            case "mcpServer/elicitation/request":
                guard let rpcID = rpcIDString(object["id"]) else { return .ignored }
                return .mcpElicitation(rpcID: rpcID, serverName: params["serverName"] as? String ?? "")

            default:
                return requestFallback(object)
            }
        }

        guard let id = object["id"] as? Int else { return .ignored }
        let result = object["result"] as? [String: Any]
        let thread = result?["thread"] as? [String: Any]
        let turn = result?["turn"] as? [String: Any]
        let errorObject = object["error"] as? [String: Any]
        return .response(
            id: id,
            threadID: thread?["id"] as? String,
            turnID: turn?["id"] as? String,
            error: errorObject?["message"] as? String
        )
    }

    static func initialize(id: Int) -> Data {
        encode([
            "jsonrpc": "2.0",
            "id": id,
            "method": "initialize",
            "params": [
                "clientInfo": ["name": "bunny", "version": "1.0"],
                "capabilities": ["experimentalApi": true],
            ],
        ])
    }

    static func initialized() -> Data {
        encode([
            "jsonrpc": "2.0",
            "method": "initialized",
        ])
    }

    static func threadStart(
        id: Int,
        cwd: String,
        approvalPolicy: String,
        sandbox: String,
        developerInstructions: String,
        writableRoots: [String],
        model: String? = nil,
        tools: BunnyToolsEndpoint? = nil
    ) -> Data {
        var params: [String: Any] = [
            "cwd": cwd,
            "approvalPolicy": approvalPolicy,
            "sandbox": sandbox,
            "developerInstructions": developerInstructions,
        ]
        if let model = AgentRunnerText.nonEmpty(model) {
            params["model"] = model
        }
        var config: [String: Any] = [:]
        if !writableRoots.isEmpty {
            config["sandbox_workspace_write"] = [
                "writable_roots": writableRoots,
            ]
        }
        if let tools {
            config["mcp_servers"] = mcpServersConfig(for: tools)
        }
        if !config.isEmpty {
            params["config"] = config
        }
        return request(id: id, method: "thread/start", params: params)
    }

    /// Model and Bunny tools are re-sent on resume: a new app-server process starts from the user's config.
    static func threadResume(id: Int, threadID: String, model: String? = nil, tools: BunnyToolsEndpoint? = nil) -> Data {
        var params: [String: Any] = ["threadId": threadID]
        if let model = AgentRunnerText.nonEmpty(model) {
            params["model"] = model
        }
        if let tools {
            params["config"] = ["mcp_servers": mcpServersConfig(for: tools)]
        }
        return request(id: id, method: "thread/resume", params: params)
    }

    /// `config.mcp_servers` for Bunny's HTTP MCP server. `default_tools_approval_mode = "approve"` lets its
    /// tools run without an approval prompt under `approvalPolicy: "never"` + `workspace-write`
    /// (see "Codex approval — resolved" in docs/superpowers/research/mcp-http.md).
    ///
    /// Codex merges this into a global `[mcp_servers.bunny]` key by key (verified; dotted
    /// `mcp_servers.bunny.*` keys behave the same). A leftover global `bearer_token_env_var` would
    /// then survive and fail startup when that variable is unset, and a null can't remove it. So the
    /// run always sets its own `bearer_token_env_var`, which Codex prefers over `http_headers`'
    /// Authorization; `CodexRunner` puts the token in that variable. The Authorization header stays for
    /// completeness.
    static func mcpServersConfig(for tools: BunnyToolsEndpoint) -> [String: Any] {
        [
            BunnyToolsEndpoint.serverName: [
                "url": tools.url,
                "http_headers": tools.headers,
                "bearer_token_env_var": BunnyToolsEndpoint.codexTokenEnvironmentVariable,
                "default_tools_approval_mode": "approve",
            ] as [String: Any],
        ]
    }

    static func turnStart(id: Int, threadID: String, text: String, effort: String? = nil) -> Data {
        var params: [String: Any] = [
            "threadId": threadID,
            "input": [["type": "text", "text": text]],
        ]
        if let effort = AgentRunnerText.nonEmpty(effort) {
            params["effort"] = effort
        }
        return request(id: id, method: "turn/start", params: params)
    }

    static func turnInterrupt(id: Int, threadID: String, turnID: String) -> Data {
        request(
            id: id,
            method: "turn/interrupt",
            params: ["threadId": threadID, "turnId": turnID]
        )
    }

    static func approvalReply(rpcID: String, approved: Bool) -> Data {
        encode([
            "jsonrpc": "2.0",
            "id": rpcIDValue(rpcID),
            "result": ["decision": approved ? "accept" : "decline"],
        ])
    }

    /// Reply to `mcpServer/elicitation/request` (McpServerElicitationRequestResponse).
    static func elicitationReply(rpcID: String, accept: Bool) -> Data {
        encode([
            "jsonrpc": "2.0",
            "id": rpcIDValue(rpcID),
            "result": [
                "action": accept ? "accept" : "decline",
                "content": NSNull(),
                "_meta": NSNull(),
            ] as [String: Any],
        ])
    }

    /// `model/list` for the Settings picker (hidden models excluded).
    static func modelList(id: Int) -> Data {
        request(id: id, method: "model/list", params: ["includeHidden": false])
    }

    /// Models from a `model/list` response line, or nil if `line` is not a successful model list.
    /// Hidden models are skipped; entries without an id are dropped.
    static func parseModelList(_ line: Data) -> [CodexModel]? {
        guard let object = jsonObject(line),
              let result = object["result"] as? [String: Any],
              let data = result["data"] as? [[String: Any]] else { return nil }
        return data.compactMap { entry in
            guard entry["hidden"] as? Bool != true,
                  let id = (entry["model"] as? String) ?? (entry["id"] as? String), !id.isEmpty else { return nil }
            let efforts = (entry["supportedReasoningEfforts"] as? [[String: Any]] ?? [])
                .compactMap { $0["reasoningEffort"] as? String }
            let displayName = AgentRunnerText.nonEmpty(entry["displayName"] as? String) ?? id
            return CodexModel(
                id: id,
                displayName: displayName,
                efforts: efforts,
                defaultEffort: entry["defaultReasoningEffort"] as? String,
                isDefault: entry["isDefault"] as? Bool ?? false
            )
        }
    }

    static func methodNotFound(rpcID: String) -> Data {
        encode([
            "jsonrpc": "2.0",
            "id": rpcIDValue(rpcID),
            "error": ["code": -32601, "message": "unsupported"],
        ])
    }

    private static func request(id: Int, method: String, params: [String: Any]) -> Data {
        encode([
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        ])
    }

    private static func requestFallback(_ object: [String: Any]) -> Incoming {
        guard let rpcID = rpcIDString(object["id"]) else { return .ignored }
        return .unsupportedRequest(rpcID: rpcID)
    }

    private static func rpcIDString(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? Int { return String(value) }
        return nil
    }

    private static func rpcIDValue(_ string: String) -> Any {
        Int(string) ?? string
    }

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func encode(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }
}
