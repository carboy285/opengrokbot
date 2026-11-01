import XCTest
#if os(macOS)
@testable import GrokBotMac
#else
@testable import GrokBot
#endif

final class RemoteProtocolTests: XCTestCase {
    func testPairingLinksRoundTripWithoutPuttingKeyInHostQuery() throws {
        let pairing = try RemotePairing(address:"https://desktop.example.ts.net:8443",token:String(repeating:"a",count:64))
        XCTAssertEqual(try RemotePairing(link:pairing.link.absoluteString),pairing)
        XCTAssertNil(URLComponents(url:pairing.baseURL,resolvingAgainstBaseURL:false)?.query)
        XCTAssertEqual(pairing.link.fragment,pairing.token)
        XCTAssertThrowsError(try RemotePairing(address:"http://public.example.com",token:pairing.token))
        XCTAssertThrowsError(try RemotePairing(address:"http://8.8.8.8",token:pairing.token))
        XCTAssertThrowsError(try RemotePairing(address:"https://user:password@example.com",token:pairing.token))
        XCTAssertThrowsError(try RemotePairing(address:"https://example.com/private",token:pairing.token))
        XCTAssertThrowsError(try RemotePairing(address:"file:///tmp",token:pairing.token))
        XCTAssertThrowsError(try RemotePairing(address:"https://example.com",token:"short"))
    }
    func testOnlyPrivateAddressesAllowDirectHTTP() {
        for host in ["192.168.1.4","10.4.3.2","172.16.1.4","100.100.10.4","127.0.0.1","my-mac.local","fd7a:115c:a1e0::1"] { XCTAssertTrue(RemotePairing.isLocalHost(host),host) }
        for host in ["192.169.0.1","172.32.1.4","100.128.1.4","8.8.8.8","example.com","192.168.1.999"] { XCTAssertFalse(RemotePairing.isLocalHost(host),host) }
    }
    func testHTTPParserHandlesFragmentedUnicodeAndChecksBearerExactly() throws {
        let token = String(repeating:"a",count:64),body = Data("{\"text\":\"café 🌎\"}".utf8)
        let head = Data("POST /v1/command HTTP/1.1\r\nAuthorization: Bearer \(token)\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
        XCTAssertNil(try HostHTTPRequest.parse(head + body.prefix(3)))
        let request = try XCTUnwrap(HostHTTPRequest.parse(head + body))
        XCTAssertTrue(request.authorized(token:token));XCTAssertFalse(request.authorized(token:String(repeating:"b",count:64)))
        XCTAssertEqual(request.body,body)
    }
    func testHTTPParserRejectsBrowserOriginsSmugglingAndOversizedBodies() {
        for request in [
            "GET /v1/state HTTP/1.1\r\nOrigin: https://evil.example\r\n\r\n",
            "POST /v1/command HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n",
            "POST /v1/command HTTP/1.1\r\nContent-Length: 200000\r\n\r\n",
            "GET /v1/state HTTP/1.1\r\nAuthorization: a\r\nAuthorization: b\r\n\r\n",
            "GET /v1/state HTTP/1.1\r\n\r\nGET /v1/state HTTP/1.1\r\n\r\n"
        ] { XCTAssertThrowsError(try HostHTTPRequest.parse(Data(request.utf8))) }
    }
}
