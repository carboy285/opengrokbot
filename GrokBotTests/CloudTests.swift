import XCTest
import CryptoKit
#if os(macOS)
@testable import GrokBotMac
#else
@testable import GrokBot
#endif

final class CloudTests: XCTestCase {
    func testEncryptionBindsOwnerPeersRequestAndDirection() throws {
        let owner = UUID(), host = CloudIdentity(), phone = CloudIdentity(), intruder = CloudIdentity(), id = UUID()
        func device(_ identity: CloudIdentity, kind: String) throws -> CloudDevice { CloudDevice(id:identity.id,name:kind,kind:kind,public_key:try identity.publicKey,last_seen:Date(),available:true) }
        let desktop = try device(host,kind:"host"), controller = try device(phone,kind:"controller")
        let plain = Data("Private chat and memory".utf8)
        let packet = try phone.seal(plain,to:desktop,owner:owner,id:id,kind:"request")
        XCTAssertEqual(try host.open(packet,from:controller,owner:owner),plain)
        XCTAssertFalse(packet.ciphertext.contains("Private"))
        XCTAssertThrowsError(try host.open(packet,from:controller,owner:UUID()))
        XCTAssertThrowsError(try intruder.open(packet,from:controller,owner:owner))
        var tampered = packet; tampered.id = UUID(); XCTAssertThrowsError(try host.open(tampered,from:controller,owner:owner))
        tampered = packet; tampered.kind = "response"; XCTAssertThrowsError(try host.open(tampered,from:controller,owner:owner))
        tampered = packet; tampered.recipient = UUID(); XCTAssertThrowsError(try host.open(tampered,from:controller,owner:owner))
        tampered = packet; tampered.created_at = Date().addingTimeInterval(-130); XCTAssertThrowsError(try host.open(tampered,from:controller,owner:owner))
        var expired = try phone.seal(plain,to:desktop,owner:owner,id:UUID(),kind:"request",now:Date().addingTimeInterval(-130))
        expired.created_at = Date() // A relay changing its timestamp cannot extend encrypted expiry.
        XCTAssertThrowsError(try host.open(expired,from:controller,owner:owner))
        let reply = try host.seal(Data("result".utf8),to:controller,owner:owner,id:id,kind:"response")
        XCTAssertEqual(try phone.open(reply,from:desktop,owner:owner),Data("result".utf8))
    }
    func testStreamingDeltaChangesDeletesAndResyncsWithoutSessions() throws {
        let bot = Workspace.fresh.bots[0]
        var previous = RemoteSnapshot(hostName:"Mac",revision:"one",workspace:Workspace(bots:[bot]),running:[],providers:[])
        previous.workspace.entries = [Entry(botID:bot.id,kind:.user,text:"hello"),Entry(botID:bot.id,kind:.bot,text:"start")]
        var next = previous; next.revision = "two"; next.workspace.entries[1].text = "streamed result"
        next.workspace.entries.append(Entry(botID:bot.id,kind:.activity,text:"done"))
        let patch = try CloudStatePatch.make(next,previous:previous)
        XCTAssertEqual(patch.snapshot.workspace.entries.count,2)
        let rebuilt = try patch.applying(to:previous)
        XCTAssertEqual(try CloudCoding.encoder().encode(rebuilt),try CloudCoding.encoder().encode(next))
        XCTAssertThrowsError(try patch.applying(to:nil))
        next.revision = "three"; next.workspace.entries.removeFirst()
        let deletion = try CloudStatePatch.make(next,previous:rebuilt)
        XCTAssertEqual(deletion.removedEntries.count,1)
        XCTAssertEqual(try deletion.applying(to:rebuilt).workspace.entries.count,2)
    }
    @MainActor
    func testLocalApprovalPinsAndRevokesIdentity() async throws {
        let secrets = KeychainSecretStore(service:"cloud-approval-test." + UUID().uuidString)
        let owner = UUID(), host = CloudIdentity(), phone = CloudIdentity()
        let session = CloudSession(access_token:"fixture",refresh_token:"refresh",expires_at:Date().timeIntervalSince1970+3600,user:CloudUser(id:owner,email:"fixture@example.test"))
        try secrets.save(JSONEncoder().encode(session),account:"session")
        defer { for key in ["session","identity-" + owner.uuidString,"approved-" + owner.uuidString,"hosts-" + owner.uuidString] { try? secrets.delete(account:key) } }
        let account = CloudAccount(kind:"host",secrets:secrets)
        var controller = CloudDevice(id:phone.id,name:"Phone",kind:"controller",public_key:try phone.publicKey,last_seen:Date(),available:true)
        XCTAssertFalse(account.approved(controller));try account.approve(controller,allowed:true);XCTAssertTrue(account.approved(controller))
        let restored = CloudAccount(kind:"host",secrets:secrets);XCTAssertTrue(restored.approved(controller))
        controller.public_key = try CloudIdentity().publicKey;XCTAssertFalse(restored.approved(controller))
        try account.approve(controller,allowed:false);XCTAssertFalse(account.approved(controller))
        var desktop = CloudDevice(id:host.id,name:"Mac",kind:"host",public_key:try host.publicKey,last_seen:Date(),available:true)
        try account.pin(desktop);desktop.public_key = try CloudIdentity().publicKey;XCTAssertThrowsError(try account.pin(desktop))
        await account.signOut();XCTAssertFalse(account.signedIn);XCTAssertNil(account.identity)
    }
}
