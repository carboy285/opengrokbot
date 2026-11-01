import Foundation
import Network

/// A small, bounded HTTP endpoint. TLS is terminated by Tailscale Serve/Funnel
/// or the user's HTTPS proxy. Direct HTTP is an explicit trusted-LAN option.
final class LocalHTTPServer: @unchecked Sendable {
    typealias Handler = @Sendable (HostHTTPRequest) async -> HostHTTPResponse
    private let queue = DispatchQueue(label: "org.opengrokbot.remote-http")
    private var listener: NWListener?
    private var connections: [UUID:NWConnection] = [:]
    private var generation = UUID()

    func start(port: UInt16, lan: Bool, handler: @escaping Handler, ready: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            stopOnQueue()
            let session = generation
            do {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(host: lan ? "0.0.0.0" : "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
                let server = try NWListener(using: parameters)
                listener = server
                server.stateUpdateHandler = { state in
                    switch state { case .ready: ready(true); case .failed: ready(false); default: break }
                }
                server.newConnectionHandler = { [weak self] connection in
                    guard let self, self.generation == session, self.connections.count < 32 else { connection.cancel(); return }
                    let id = UUID(); self.connections[id] = connection
                    connection.start(queue: self.queue)
                    self.queue.asyncAfter(deadline: .now() + 20) { [weak self, weak connection] in connection?.cancel(); self?.connections[id] = nil }
                    self.receive(connection, id: id, buffer: Data(), handler: handler)
                }
                server.start(queue: queue)
            } catch { ready(false) }
        }
    }
    func stop() { queue.async { [self] in stopOnQueue() } }
    private func stopOnQueue() {
        generation = UUID(); listener?.cancel(); listener = nil
        for connection in connections.values { connection.cancel() }; connections.removeAll()
    }
    private func receive(_ connection: NWConnection, id: UUID, buffer: Data, handler: @escaping Handler) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            let bytes = buffer + (data ?? Data())
            do {
                if let request = try HostHTTPRequest.parse(bytes) {
                    Task {
                        let response = await handler(request)
                        connection.send(content: response.wireData, completion: .contentProcessed { _ in connection.cancel(); self.queue.async { self.connections[id] = nil } })
                    }
                } else if complete || error != nil || bytes.count > 139264 { connection.cancel(); self.connections[id] = nil }
                else { self.receive(connection, id: id, buffer: bytes, handler: handler) }
            } catch {
                connection.send(content: HostHTTPResponse.error(400, "Invalid request").wireData, completion: .contentProcessed { _ in connection.cancel(); self.queue.async { self.connections[id] = nil } })
            }
        }
    }
}
