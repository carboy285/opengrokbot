import XCTest
#if os(macOS)
@testable import GrokBotMac
#else
@testable import GrokBot
#endif

private final class AuthFixture: @unchecked Sendable {
    let owner = UUID()
    let lock = NSLock()
    private var refreshes = 0
    var refreshCount: Int { lock.lock();defer{lock.unlock()};return refreshes }
    func reply(_ request: URLRequest) throws -> Data {
        XCTAssertEqual(request.value(forHTTPHeaderField:"apikey"),CloudConfiguration.publishableKey)
        if request.url?.path == "/auth/v1/token" {
            XCTAssertEqual(URLComponents(url:request.url!,resolvingAgainstBaseURL:false)?.queryItems?.first?.value,"refresh_token")
            lock.lock();refreshes += 1;lock.unlock()
            // Keep refresh in flight while the second authenticated request starts.
            Thread.sleep(forTimeInterval:0.15)
            return try JSONEncoder().encode(CloudSession(access_token:"fresh-access",refresh_token:"rotated-refresh",expires_in:3600,user:CloudUser(id:owner,email:"auth@example.test")))
        }
        XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer fresh-access")
        return Data("[]".utf8)
    }
}
private final class AuthURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var fixture: AuthFixture?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == CloudConfiguration.url.host }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let data = try Self.fixture!.reply(request)
            client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self,didFailWithError:error) }
    }
    override func stopLoading() {}
}
final class CloudAuthTests: XCTestCase {
    @MainActor
    func testConcurrentRequestsRefreshOnceAndPersistRotatedToken() async throws {
        let fixture = AuthFixture();AuthURLProtocol.fixture = fixture
        let config = URLSessionConfiguration.ephemeral;config.protocolClasses = [AuthURLProtocol.self]
        let secrets = KeychainSecretStore(service:"cloud-auth-test." + UUID().uuidString)
        defer { AuthURLProtocol.fixture = nil;for key in ["session","identity-" + fixture.owner.uuidString] { try? secrets.delete(account:key) } }
        let expired = CloudSession(access_token:"expired",refresh_token:"old-refresh",expires_at:0,user:CloudUser(id:fixture.owner,email:"auth@example.test"))
        try secrets.save(JSONEncoder().encode(expired),account:"session")
        let account = CloudAccount(kind:"controller",secrets:secrets,configuration:config)
        let first = Task { try await account.request(path:"/rest/v1/opengrok_devices",method:"GET") }
        let second = Task { try await account.request(path:"/rest/v1/opengrok_devices",method:"GET") }
        _ = try await first.value;_ = try await second.value
        XCTAssertEqual(fixture.refreshCount,1)
        let saved = try JSONDecoder().decode(CloudSession.self,from:XCTUnwrap(secrets.read(account:"session")))
        XCTAssertEqual(saved.refresh_token,"rotated-refresh");XCTAssertGreaterThan(saved.expires_at ?? 0,Date().timeIntervalSince1970 + 3000)
        XCTAssertEqual(account.session?.access_token,"fresh-access")
    }
}
