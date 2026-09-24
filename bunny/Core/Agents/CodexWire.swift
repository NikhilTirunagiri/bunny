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
        writableRoots: [String]
    ) -> Data {
        var params: [String: Any] = [
            "cwd": cwd,
            "approvalPolicy": approvalPolicy,
            "sandbox": sandbox,
            "developerInstructions": developerInstructions,
        ]
        if !writableRoots.isEmpty {
            params["config"] = [
                "sandbox_workspace_write": [
                    "writable_roots": writableRoots,
                ],
            ]
        }
        return request(id: id, method: "thread/start", params: params)
    }

    static func threadResume(id: Int, threadID: String) -> Data {
        request(id: id, method: "thread/resume", params: ["threadId": threadID])
    }

    static func turnStart(id: Int, threadID: String, text: String) -> Data {
        request(
            id: id,
            method: "turn/start",
            params: [
                "threadId": threadID,
                "input": [["type": "text", "text": text]],
            ]
        )
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
