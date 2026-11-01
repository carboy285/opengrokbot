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
        try await account.send(CloudCoding.encoder().encode(request),to:peer,id:id,kind:"request")
        let deadline = Date().addingTimeInterval(35)
        while Date() < deadline {
            try Task.checkCancellation()
            guard account.session?.user.id == owner else { throw CloudError.signedOut }
            for packet in try await account.poll() {
                guard packet.id == id, packet.sender == peer.id, packet.kind == "response" else { try? await account.acknowledge(packet); continue }
                let data = try account.decrypt(packet,peer:peer)
                let response = try CloudCoding.decoder().decode(CloudResponse.self,from:data)
                try? await account.acknowledge(packet)
                guard (200...299).contains(response.status) else {
                    if response.status == 403 { throw CloudError.approvalRequired }
                    let object = try? JSONDecoder().decode([String:String].self,from:response.body)
                    throw CloudError.message(object?["error"] ?? "Desktop request failed (\(response.status)).")
                }; return response
            }
            try await Task.sleep(for:.milliseconds(500))
        }; throw CloudError.timeout
    }
}
