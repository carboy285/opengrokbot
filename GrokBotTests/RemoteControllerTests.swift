#if os(iOS)
import XCTest
@testable import GrokBot

private final class ControllerFixture: @unchecked Sendable {
    let lock = NSLock()
    var workspace = Workspace.fresh
    var revision = 0
    var offline = false
    func respond(_ request: URLRequest) throws -> Data {
        lock.lock();defer { lock.unlock() }
        if offline { throw URLError(.notConnectedToInternet) }
        if request.url?.path == "/v1/command" {
            var data = request.httpBody ?? Data()
            if data.isEmpty, let stream = request.httpBodyStream {
                stream.open();defer { stream.close() };var buffer=[UInt8](repeating:0,count:4096)
                while true { let length=stream.read(&buffer,maxLength:buffer.count);if length<=0 {break};data.append(contentsOf:buffer.prefix(length)) }
            }
            let command = try JSONDecoder().decode(RemoteCommand.self,from:data)
            if command.action == "send", let bot = workspace.bots.first, let text = command.text {
                workspace.entries.append(Entry(botID:bot.id,kind:.user,text:text,id:command.requestID))
                workspace.entries.append(Entry(botID:bot.id,kind:.bot,text:"Host reply"));revision += 1
            }
            return Data("{\"accepted\":true}".utf8)
        }
        let encoder=JSONEncoder();encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(RemoteSnapshot(hostName:"My Mac",revision:String(revision),workspace:workspace,running:[],providers:[RemoteProvider(provider:.codex,version:"fixture")],defaultProvider:.codex))
    }
    func setOffline(_ value: Bool) { lock.lock();offline=value;lock.unlock() }
    var entryCount: Int { lock.lock();defer{lock.unlock()};return workspace.entries.count }
}
private final class ControllerURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var fixture: ControllerFixture?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "desktop.example.ts.net" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let fixture = Self.fixture, request.value(forHTTPHeaderField:"Authorization") == "Bearer " + String(repeating:"a",count:64) else { throw RemoteError.unauthorized }
            let data=try fixture.respond(request),response=HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"application/json"])!
            client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self,didFailWithError:error) }
    }
    override func stopLoading() {}
}
final class RemoteControllerTests: XCTestCase {
    @MainActor
    func testPhoneControlsHostAndReconnectsWithoutCreatingLocalWorkspace() async throws {
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[ControllerURLProtocol.self]
        let fixture=ControllerFixture();ControllerURLProtocol.fixture=fixture
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store=WorkspaceStore(url:root.appendingPathComponent("phone.json")),app=AppModel(store:store)
        let secrets=KeychainSecretStore(service:"remote-controller-test."+UUID().uuidString)
        let remote=RemoteController(client:RemoteHTTPClient(configuration:config),secrets:secrets)
        defer{remote.disconnect();ControllerURLProtocol.fixture=nil;try? secrets.delete(account:"desktop");try? FileManager.default.removeItem(at:root)}
        remote.attach(app)
        XCTAssertTrue(app.workspace.bots.isEmpty)
        let pairing=try RemotePairing(address:"https://desktop.example.ts.net:8443",token:String(repeating:"a",count:64))
        await remote.connect(link:pairing.link.absoluteString)
        XCTAssertTrue(remote.online);XCTAssertTrue(remote.hasSnapshot);XCTAssertEqual(remote.hostName,"My Mac")
        let bot=try XCTUnwrap(app.workspace.bots.first)
        let accepted=await remote.send("Use my desktop model",bot:bot)
        XCTAssertTrue(accepted);XCTAssertEqual(fixture.entryCount,2);XCTAssertEqual(app.entries(for:bot).last?.text,"Host reply")
        XCTAssertFalse(FileManager.default.fileExists(atPath:store.url.path),"A controller must not save an independent Bot workspace")
        fixture.setOffline(true)
        for _ in 0..<40 { if !remote.online {break};try await Task.sleep(for:.milliseconds(100)) }
        XCTAssertFalse(remote.online);XCTAssertTrue(remote.hasSnapshot)
        fixture.setOffline(false)
        for _ in 0..<60 { if remote.online {break};try await Task.sleep(for:.milliseconds(100)) }
        XCTAssertTrue(remote.online);XCTAssertEqual(app.workspace.bots.first?.id,bot.id)
        remote.disconnect();XCTAssertTrue(app.workspace.bots.isEmpty);XCTAssertEqual(fixture.entryCount,2)
    }
}
#endif
