import Foundation

/// Serial RPCs keep state deltas ordered and prevent one poll consuming another RPC's reply.
@MainActor
final class CloudRelayClient {
    let account: CloudAccount
    private var inFlight = false
    init(account: CloudAccount) { self.account = account }
    func fetch(_ peer: CloudDevice, target: String, command: RemoteCommand? = nil) async throws -> CloudResponse {
        while inFlight { try await Task.sleep(for:.milliseconds(50)) }; inFlight = true; defer { inFlight = false }
        try Task.checkCancellation(); try account.pin(peer)
        let id = UUID(), owner = account.session?.user.id
        let request = CloudRequest(method:command == nil ? "GET":"POST",target:target,body:try command.map { try CloudCoding.encoder().encode($0) } ?? Data())
        let payload = try CloudCoding.encoder().encode(request)
        try await account.send(payload,to:peer,id:id,kind:"request")
        let started = Date(), deadline = Date().addingTimeInterval(command == nil ? 12 : 35)
        var nextResend = Date().addingTimeInterval(2)
        while Date() < deadline {
            try Task.checkCancellation()
            guard account.session?.user.id == owner else { throw CloudError.signedOut }
            for packet in try await account.poll() {
                guard packet.id == id, packet.sender == peer.id, packet.kind == "response" else { try? await account.acknowledge(packet); continue }
                let response: CloudResponse
                do {
                    let data = try account.decrypt(packet,peer:peer)
                    response = try CloudCoding.decoder().decode(CloudResponse.self,from:data)
                } catch {
                    try? await account.acknowledge(packet)
                    throw CloudError.message("A reply from \(peer.name) could not be verified or decoded. Quit older copies of OpenGrokBot on that computer and reopen the updated app.")
                }
                try? await account.acknowledge(packet)
                guard (200...299).contains(response.status) else {
                    if response.status == 403 { throw CloudError.approvalRequired }
                    let object = try? JSONDecoder().decode([String:String].self,from:response.body)
                    throw CloudError.message(object?["error"] ?? "Desktop request failed (\(response.status)).")
                }; return response
            }
            if Date() >= nextResend {
                try await account.send(payload,to:peer,id:id,kind:"request")
                nextResend = Date().addingTimeInterval(3)
            }
            let elapsed = Date().timeIntervalSince(started)
            try await Task.sleep(for: elapsed < 2 ? .milliseconds(100) : elapsed < 6 ? .milliseconds(250) : .milliseconds(500))
        }; throw CloudError.timeout
    }
}
