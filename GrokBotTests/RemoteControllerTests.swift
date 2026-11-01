#if os(iOS)
import XCTest
@testable import GrokBot

private final class ControllerFixture: @unchecked Sendable {
    let lock = NSLock()
    let owner = UUID()
    let host = CloudIdentity()
    var phone: CloudDevice?
    var workspace = Workspace.fresh
    var revision = 0
    var offline = false
    var packets: [CloudPacket] = []
    var previous: RemoteSnapshot?
    func respond(_ request: URLRequest) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        if offline { throw URLError(.notConnectedToInternet) }
        var bytes = request.httpBody ?? Data()
        if bytes.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() };var buffer = [UInt8](repeating:0,count:4096)
            while true { let length = stream.read(&buffer,maxLength:buffer.count); if length <= 0 { break }; bytes.append(contentsOf:buffer.prefix(length)) }
        }
        let body = (try? JSONDecoder().decode([String:String].self,from:bytes)) ?? [:]
        let encoder = CloudCoding.encoder()
        if request.url?.path == "/auth/v1/token" {
            return try encoder.encode(CloudSession(access_token:"fixture-token",refresh_token:"fixture-refresh",expires_at:Date().timeIntervalSince1970 + 3600,user:CloudUser(id:owner,email:"test@example.test")))
        }
        guard request.value(forHTTPHeaderField:"Authorization") == "Bearer fixture-token" else { throw RemoteError.unauthorized }
        if request.url?.path == "/rest/v1/rpc/opengrok_register_device" {
            phone = CloudDevice(id:UUID(uuidString:body["device_id"]!)!,name:"iPhone",kind:"controller",public_key:body["device_key"]!,last_seen:Date(),available:true)
        } else if request.url?.path == "/rest/v1/opengrok_devices" {
            return try encoder.encode([CloudDevice(id:host.id,name:"My Mac",kind:"host",public_key:try host.publicKey,last_seen:Date(),available:true)] + [phone].compactMap{$0})
        } else if request.url?.path == "/rest/v1/rpc/opengrok_send", let phone {
            let packet = CloudPacket(id:UUID(uuidString:body["packet_id"]!)!,sender:phone.id,recipient:host.id,kind:"request",ciphertext:body["payload"]!,created_at:Date())
            let command = try CloudCoding.decoder().decode(CloudRequest.self,from:host.open(packet,from:phone,owner:owner))
            let response: CloudResponse
            if command.target == "/v1/command" {
                let action = try JSONDecoder().decode(RemoteCommand.self,from:command.body)
                if action.action == "send", let bot = workspace.bots.first, let text = action.text, !workspace.entries.contains(where:{$0.id == action.requestID}) {
                    workspace.entries.append(Entry(botID:bot.id,kind:.user,text:text,id:action.requestID))
                    workspace.entries.append(Entry(botID:bot.id,kind:.bot,text:"Host reply"));revision += 1
                }
                response = CloudResponse(status:200,body:Data("{\"accepted\":true}".utf8))
            } else {
                let snapshot = RemoteSnapshot(hostName:"My Mac",revision:String(revision),workspace:workspace,running:[],providers:[RemoteProvider(provider:.codex,version:"fixture")],defaultProvider:.codex)
                let since = URLComponents(string:command.target)?.queryItems?.first(where:{$0.name == "since"})?.value
                response = since == snapshot.revision ? CloudResponse(status:204,body:Data()):CloudResponse(status:200,body:try encoder.encode(CloudStatePatch.make(snapshot,previous:previous?.revision == since ? previous:nil)))
                previous = snapshot
            }
            packets.append(try host.seal(encoder.encode(response),to:phone,owner:owner,id:packet.id,kind:"response"))
        } else if request.url?.path == "/rest/v1/rpc/opengrok_poll" { return try encoder.encode(packets) }
        else if request.url?.path == "/rest/v1/rpc/opengrok_ack" { packets.removeAll { $0.id.uuidString.lowercased() == body["packet_id"]?.lowercased() } }
        return Data("null".utf8)
    }
    func setOffline(_ value: Bool) { lock.lock();offline = value;lock.unlock() }
    var entryCount: Int { lock.lock();defer{lock.unlock()};return workspace.entries.count }
}
private final class ControllerURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var fixture: ControllerFixture?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == CloudConfiguration.url.host }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let fixture = Self.fixture else { throw RemoteError.unavailable }
            let data = try fixture.respond(request), response = HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!
            client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self,didFailWithError:error) }
    }
    override func stopLoading() {}
}
final class RemoteControllerTests: XCTestCase {
    @MainActor
    func testAccountControllerEncryptedCommandsReconnectWithoutLocalWorkspace() async throws {
        let config = URLSessionConfiguration.ephemeral;config.protocolClasses = [ControllerURLProtocol.self]
        let fixture = ControllerFixture();ControllerURLProtocol.fixture = fixture
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = WorkspaceStore(url:root.appendingPathComponent("phone.json")), app = AppModel(store:store)
        let secrets = KeychainSecretStore(service:"cloud-controller-test." + UUID().uuidString)
        let account = CloudAccount(kind:"controller",secrets:secrets,configuration:config)
        let remote = RemoteController(account:account,secrets:secrets)
        defer { remote.disconnect();ControllerURLProtocol.fixture = nil;for key in ["session","identity-" + fixture.owner.uuidString,"hosts-" + fixture.owner.uuidString,fixture.owner.uuidString] { try? secrets.delete(account:key) };try? FileManager.default.removeItem(at:root) }
        remote.attach(app);XCTAssertTrue(app.workspace.bots.isEmpty)
        await account.signIn(email:"test@example.test",password:"fixture-pass",create:false)
        XCTAssertTrue(account.signedIn)
        for _ in 0..<100 { if remote.online {break};try await Task.sleep(for:.milliseconds(100)) }
        XCTAssertTrue(remote.online,remote.status);XCTAssertTrue(remote.hasSnapshot);XCTAssertEqual(remote.hostName,"My Mac")
        let bot = try XCTUnwrap(app.workspace.bots.first)
        let accepted = await remote.send("Use my desktop model",bot:bot)
        XCTAssertTrue(accepted);XCTAssertEqual(fixture.entryCount,2);XCTAssertEqual(app.entries(for:bot).last?.text,"Host reply")
        XCTAssertFalse(FileManager.default.fileExists(atPath:store.url.path),"The phone must never save an independent workspace")
        fixture.setOffline(true)
        for _ in 0..<70 { if !remote.online {break};try await Task.sleep(for:.milliseconds(100)) }
        XCTAssertFalse(remote.online);XCTAssertTrue(remote.hasSnapshot)
        fixture.setOffline(false)
        for _ in 0..<100 { if remote.online {break};try await Task.sleep(for:.milliseconds(100)) }
        XCTAssertTrue(remote.online,remote.status);XCTAssertEqual(app.workspace.bots.first?.id,bot.id)
        remote.disconnect();XCTAssertTrue(app.workspace.bots.isEmpty);XCTAssertEqual(fixture.entryCount,2)
        remote.setActive(false)
    }
}
#endif
