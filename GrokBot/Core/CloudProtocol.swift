import Foundation
import CryptoKit

/// Public client configuration. Never put a service-role key in an app.
enum CloudConfiguration {
    static let url = URL(string: "https://kiaenmbtsgoxvfsijzzc.supabase.co")!
    static let publishableKey = "sb_publishable_iDMMZU6icZ1Wjwrv_zkbLw_W4pr-nCK"
    static let callback = "opengrokbot://auth/callback"
}
struct CloudUser: Codable, Sendable { let id: UUID; var email: String? }
struct CloudSession: Codable, Sendable {
    var access_token: String
    var refresh_token: String
    var expires_at: Double?
    var expires_in: Double?
    var user: CloudUser
    mutating func setExpiry() { if expires_at == nil { expires_at = Date().timeIntervalSince1970 + (expires_in ?? 3600) } }
}
struct CloudDevice: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var kind: String
    var public_key: String
    var last_seen: Date
    var available: Bool
    var online: Bool { available && Date().timeIntervalSince(last_seen) < 65 }
    /// Compare these words on both devices before approving first access.
    var fingerprint: String { SHA256.hash(data: Data(base64Encoded: public_key) ?? Data()).prefix(6).map { String(format: "%02x", $0) }.joined(separator: " ") }
}
struct CloudIdentity: Codable, Sendable {
    var id: UUID = UUID()
    var privateKey: Data = Curve25519.KeyAgreement.PrivateKey().rawRepresentation
    var key: Curve25519.KeyAgreement.PrivateKey { get throws { try .init(rawRepresentation: privateKey) } }
    var publicKey: String { get throws { try key.publicKey.rawRepresentation.base64EncodedString() } }
    func context(owner: UUID, sender: UUID, recipient: UUID, id: UUID, kind: String) -> Data {
        Data("OpenGrokBot/1|\(owner)|\(sender)|\(recipient)|\(id)|\(kind)".lowercased().utf8)
    }
    private func sharedKey(peer: CloudDevice, owner: UUID) throws -> SymmetricKey {
        guard let bytes = Data(base64Encoded: peer.public_key) else { throw CloudError.invalidPacket }
        let shared = try key.sharedSecretFromKeyAgreement(with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: bytes))
        let peers = [id.uuidString, peer.id.uuidString].sorted().joined(separator: "|").lowercased()
        return shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(owner.uuidString.lowercased().utf8), sharedInfo: Data(("OpenGrokBot/relay/v1|" + peers).utf8), outputByteCount: 32)
    }
    func seal(_ data: Data, to peer: CloudDevice, owner: UUID, id: UUID, kind: String, now: Date = Date()) throws -> CloudPacket {
        guard data.count <= 5_900_000 else { throw CloudError.message("This workspace is too large to transfer. Export older conversations on the desktop first.") }
        // Expiry is inside the authenticated ciphertext; the relay cannot extend replay lifetime.
        let expiry = UInt64(now.addingTimeInterval(90).timeIntervalSince1970)
        let envelope = Data((0..<8).reversed().map { UInt8(truncatingIfNeeded: expiry >> ($0 * 8)) }) + data
        let box = try AES.GCM.seal(envelope, using: sharedKey(peer: peer, owner: owner), authenticating: context(owner: owner, sender: self.id, recipient: peer.id, id: id, kind: kind))
        guard let combined = box.combined else { throw CloudError.invalidPacket }
        return CloudPacket(id: id, sender: self.id, recipient: peer.id, kind: kind, ciphertext: combined.base64EncodedString(), created_at: now)
    }
    func open(_ packet: CloudPacket, from peer: CloudDevice, owner: UUID, now: Date = Date()) throws -> Data {
        guard packet.sender == peer.id, packet.recipient == id, ["request","response"].contains(packet.kind), abs(packet.created_at.timeIntervalSince(now)) < 120,
              let bytes = Data(base64Encoded: packet.ciphertext), bytes.count <= 6_000_036 else { throw CloudError.invalidPacket }
        let envelope = try AES.GCM.open(AES.GCM.SealedBox(combined: bytes), using: sharedKey(peer: peer, owner: owner), authenticating: context(owner: owner, sender: peer.id, recipient: id, id: packet.id, kind: packet.kind))
        guard envelope.count >= 8 else { throw CloudError.invalidPacket }
        let expiry = envelope.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard Double(expiry) > now.timeIntervalSince1970, Double(expiry) < now.timeIntervalSince1970 + 120 else { throw CloudError.invalidPacket }
        return Data(envelope.dropFirst(8))
    }
}
struct CloudPacket: Codable, Sendable {
    var id: UUID
    var sender: UUID
    var recipient: UUID
    var kind: String
    var ciphertext: String
    var created_at: Date
}
struct CloudRequest: Codable, Sendable { var method: String; var target: String; var body: Data = Data() }
struct CloudResponse: Codable, Sendable { var status: Int; var body: Data }

/// Streaming updates transfer changed entries rather than the entire chat every poll.
struct CloudStatePatch: Codable, Sendable {
    var snapshot: RemoteSnapshot
    var baseRevision: String?
    var removedEntries: [UUID]
    static func make(_ next: RemoteSnapshot, previous: RemoteSnapshot?) throws -> CloudStatePatch {
        guard let previous else { return CloudStatePatch(snapshot: next, baseRevision: nil, removedEntries: []) }
        var result = next
        let encoder = CloudCoding.encoder()
        let old = try Dictionary(uniqueKeysWithValues: previous.workspace.entries.map { ($0.id, try encoder.encode($0)) })
        result.workspace.entries = try next.workspace.entries.filter { try old[$0.id] != encoder.encode($0) }
        let present = Set(next.workspace.entries.map(\.id))
        return CloudStatePatch(snapshot: result, baseRevision: previous.revision, removedEntries: previous.workspace.entries.map(\.id).filter { !present.contains($0) })
    }
    func applying(to previous: RemoteSnapshot?) throws -> RemoteSnapshot {
        guard let baseRevision else { return snapshot }
        guard let previous, previous.revision == baseRevision else { throw CloudError.resync }
        var result = snapshot
        let removed = Set(removedEntries), changes = Dictionary(uniqueKeysWithValues: snapshot.workspace.entries.map { ($0.id, $0) })
        let existing = Set(previous.workspace.entries.map(\.id))
        result.workspace.entries = previous.workspace.entries.filter { !removed.contains($0.id) }.map { changes[$0.id] ?? $0 } + snapshot.workspace.entries.filter { !existing.contains($0.id) }
        return result
    }
}
enum CloudCoding {
    static func encoder() -> JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e }
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
            if let date = f.date(from: value) { return date }; f.formatOptions = [.withInternetDateTime]
            guard let date = f.date(from: value) else { throw CloudError.invalidPacket }; return date
        }; return d
    }
}
enum CloudError: LocalizedError {
    case message(String), invalidPacket, resync, signedOut, timeout, approvalRequired
    var errorDescription: String? {
        switch self {
        case .message(let text): text
        case .invalidPacket: "The device message could not be verified."
        case .resync: "Refreshing the desktop workspace…"
        case .signedOut: "Sign in to your OpenGrokBot account."
        case .timeout: "The desktop did not respond. Keep it awake, enable phone access, and approve this phone on the desktop."
        case .approvalRequired: "Your Mac is connected, but this iPhone needs approval. On the Mac, open Settings → Computer, compare this phone’s fingerprint, and choose Approve phone. Your Bots will load automatically."
        }
    }
}
