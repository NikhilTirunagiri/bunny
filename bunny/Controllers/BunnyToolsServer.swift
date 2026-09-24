import Foundation
import Network
import Observation
import os

/// Bunny's local MCP server ("Bunny tools", spec §5): `POST http://127.0.0.1:<port>/mcp`, bearer-token
/// auth, one request per connection. Bound to loopback only. All Network callbacks run on the main
/// queue, so parsing, `MCPServerCore.handle` and the SwiftData backend all run on the main actor.
/// Observable, so Settings shows the bound port as it changes.
@MainActor
@Observable
final class BunnyToolsServer {
    static let shared = BunnyToolsServer()
    private init() {}

    /// The actual bound port, or nil when the server isn't running (yet).
    private(set) var port: Int?

    /// Executes tool calls. Must be set before `start()`.
    @ObservationIgnored var backend: BunnyToolsBackend?

    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var core: MCPServerCore?
    @ObservationIgnored private var connections: [ObjectIdentifier: NWConnection] = [:]
    /// Bumped on every start/stop, so callbacks from a replaced listener are ignored.
    @ObservationIgnored private var generation = 0
    /// One delayed retry after both the fixed and the fallback port failed; `restart()` re-arms it.
    @ObservationIgnored private var didRetry = false

    private static let log = Logger(subsystem: "bunny", category: "BunnyTools")
    private static let maxConnections = 32
    private static let connectionTimeout: TimeInterval = 30
    private static let retryDelay: TimeInterval = 5

    var isRunning: Bool { port != nil }

    /// Starts listening on `AgentSettings.toolsPort`; if that port is taken, on a free port picked by the OS.
    func start() {
        guard listener == nil, let backend else { return }
        core = MCPServerCore(token: AgentSettings.toolsToken, backend: backend)
        listen(on: AgentSettings.toolsPort, allowFallback: true)
    }

    /// Stops listening and closes every open connection.
    func stop() {
        generation += 1
        listener?.cancel()
        listener = nil
        core = nil
        port = nil
        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()
    }

    /// Restarts on the current settings (e.g. after the token was regenerated).
    func restart() {
        stop()
        didRetry = false
        start()
    }

    // MARK: - Listener

    private func listen(on requestedPort: Int, allowFallback: Bool) {
        generation += 1
        let current = generation
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: max(0, requestedPort))) else { return }

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: nwPort)
        parameters.acceptLocalOnly = true
        // A restart rebinds the port right after the old listener closed.
        parameters.allowLocalEndpointReuse = true

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            Self.log.error("Bunny tools: couldn't create listener on port \(requestedPort): \(error.localizedDescription, privacy: .public)")
            listenFailed(requestedPort: requestedPort, allowFallback: allowFallback)
            return
        }
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                self?.listenerStateChanged(state, generation: current, requestedPort: requestedPort,
                                           allowFallback: allowFallback)
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else {
                    connection.cancel()
                    return
                }
                self.accept(connection)
            }
        }
        listener.start(queue: .main)
    }

    private func listenerStateChanged(_ state: NWListener.State, generation current: Int, requestedPort: Int,
                                      allowFallback: Bool) {
        guard generation == current, let listener else { return }
        switch state {
        case .ready:
            port = listener.port.map { Int($0.rawValue) }
            Self.log.info("Bunny tools listening on 127.0.0.1:\(self.port ?? 0, privacy: .public)")
        case .failed(let error), .waiting(let error):
            listener.stateUpdateHandler = nil
            listener.cancel()
            self.listener = nil
            port = nil
            Self.log.error("Bunny tools: port \(requestedPort) unavailable: \(error.localizedDescription, privacy: .public)")
            listenFailed(requestedPort: requestedPort, allowFallback: allowFallback)
        default:
            break
        }
    }

    /// The fixed port failed → try a free port. The free port failed too → start over once, after 5 s.
    private func listenFailed(requestedPort: Int, allowFallback: Bool) {
        if allowFallback && requestedPort != 0 {
            listen(on: 0, allowFallback: false)
            return
        }
        guard !didRetry else {
            Self.log.error("Bunny tools: not running (the retry failed too)")
            return
        }
        didRetry = true
        let current = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelay) { [weak self] in
            MainActor.assumeIsolated {
                // Skip when stopped or restarted meanwhile.
                guard let self, self.generation == current, self.listener == nil else { return }
                self.start()
            }
        }
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        guard connections.count < Self.maxConnections else {
            connection.cancel()
            return
        }
        let key = ObjectIdentifier(connection)
        connections[key] = connection
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                switch state {
                case .failed:
                    // A failed connection still holds its resources until cancelled.
                    self?.connections[key] = nil
                    connection.cancel()
                case .cancelled:
                    self?.connections[key] = nil
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
        receive(on: connection, buffer: Data())

        // Drop connections that never finish sending a request.
        let current = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.connectionTimeout) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current, self.connections[key] != nil else { return }
                self.close(connection)
            }
        }
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, self.connections[ObjectIdentifier(connection)] != nil else { return }
                if error != nil {
                    self.close(connection)
                    return
                }
                var buffer = buffer
                if let data {
                    buffer.append(data)
                }
                switch HTTPMessageCodec.parse(buffer) {
                case .complete(let request):
                    self.respond(to: request, on: connection)
                case .failure(let status):
                    self.send(HTTPMessageCodec.statusResponse(status), on: connection)
                case .incomplete:
                    if isComplete {
                        // The client closed its side before sending a whole request.
                        self.close(connection)
                    } else {
                        self.receive(on: connection, buffer: buffer)
                    }
                }
            }
        }
    }

    private func respond(to request: HTTPRequestLite, on connection: NWConnection) {
        guard let core else {
            send(HTTPMessageCodec.statusResponse(503), on: connection)
            return
        }
        send(core.handle(request), on: connection)
    }

    private func send(_ response: HTTPResponseLite, on connection: NWConnection) {
        connection.send(content: HTTPMessageCodec.encode(response), contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { [weak self] _ in
                            MainActor.assumeIsolated {
                                self?.close(connection)
                            }
                        })
    }

    private func close(_ connection: NWConnection) {
        connections[ObjectIdentifier(connection)] = nil
        connection.cancel()
    }
}
