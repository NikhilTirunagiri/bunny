import Foundation

/// One entry of Codex's `model/list` (the models the Settings picker offers).
struct CodexModel: Equatable, Sendable {
    /// Model slug passed as `model` on `thread/start`.
    let id: String
    let displayName: String
    /// Supported reasoning efforts, in the CLI's order (e.g. low … max).
    let efforts: [String]
    let defaultEffort: String?
    /// The account's default model.
    let isDefault: Bool
}

/// Asks the local Codex CLI which models it offers, via a short-lived `codex app-server --stdio`.
enum CodexModelCatalog {
    private static let initializeID = 1
    private static let modelListID = 2

    /// Launches `cliPath app-server --stdio`, sends `initialize` / `initialized` / `model/list`, then
    /// terminates it. Completes exactly once, on the main queue: the models, or nil on a launch error,
    /// an error response, an early exit or after `timeout` seconds. Callable from any thread.
    nonisolated static func fetch(
        cliPath: String,
        environment: [String: String],
        timeout: TimeInterval = 8,
        completion: @escaping @Sendable ([CodexModel]?) -> Void
    ) {
        DispatchQueue.main.async {
            // AgentProcess lives on the main thread (and is @MainActor in the app target).
            MainActor.assumeIsolated {
                Fetch(cliPath: cliPath, environment: environment, completion: completion).start(timeout: timeout)
            }
        }
    }

    /// One fetch's state. Main thread only; kept alive by its process callbacks and timeout until it finishes.
    private final class Fetch {
        private let process: AgentProcess
        private let completion: @Sendable ([CodexModel]?) -> Void
        private var finished = false

        init(cliPath: String, environment: [String: String], completion: @escaping @Sendable ([CodexModel]?) -> Void) {
            self.process = AgentProcess(
                executable: cliPath,
                arguments: ["app-server", "--stdio"],
                cwd: FileManager.default.homeDirectoryForCurrentUser.path,
                environment: environment
            )
            self.completion = completion
        }

        func start(timeout: TimeInterval) {
            process.onLine = { line in self.handle(line) }
            process.onExit = { _, _ in self.finish(nil) }
            do {
                try process.start()
            } catch {
                finish(nil)
                return
            }
            process.write(CodexWire.initialize(id: CodexModelCatalog.initializeID))
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                self.finish(nil)
            }
        }

        private func handle(_ line: Data) {
            switch CodexWire.parse(line) {
            case let .response(id, _, _, error) where id == CodexModelCatalog.initializeID:
                guard error == nil else {
                    finish(nil)
                    return
                }
                process.write(CodexWire.initialized())
                process.write(CodexWire.modelList(id: CodexModelCatalog.modelListID))
            case let .response(id, _, _, _) where id == CodexModelCatalog.modelListID:
                // nil for an error response.
                finish(CodexWire.parseModelList(line))
            case let .unsupportedRequest(rpcID), let .approvalRequest(rpcID, _, _, _), let .mcpElicitation(rpcID, _):
                process.write(CodexWire.methodNotFound(rpcID: rpcID))
            default:
                break
            }
        }

        private func finish(_ models: [CodexModel]?) {
            guard !finished else { return }
            finished = true
            // Break the process -> closure -> self cycle.
            process.onLine = nil
            process.onExit = nil
            process.terminate()
            completion(models)
        }
    }
}
