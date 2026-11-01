#if os(macOS)
import XCTest
@testable import GrokBotMac

final class ComposioMockProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class MacComposioTests: XCTestCase {
    func testProjectSessionAndOAuthUseDocumentedRoutes() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ComposioMockProtocol.self]
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel(); ComposioMockProtocol.handler = nil }
        ComposioMockProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-project-key")
            XCTAssertEqual(request.url?.host, "backend.composio.dev")
            switch request.url!.path {
            case "/api/v3.1/tool_router/session":
                XCTAssertEqual(request.httpMethod, "POST")
                let data: Data
                if let body = request.httpBody { data = body }
                else {
                    let stream = request.httpBodyStream!; stream.open(); defer { stream.close() }
                    var result = Data(), buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; result.append(contentsOf: buffer.prefix(n)) }; data = result
                }
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String:Any])
                XCTAssertEqual(body["user_id"] as? String, "device-unique-user")
                XCTAssertEqual((body["toolkits"] as? [String:[String]])?["enable"], ["github"])
                return (201, #"{"session_id":"trs_fixture","mcp":{"url":"https://connect.composio.dev/mcp/fixture"}}"#)
            case "/api/v3.1/tool_router/session/trs_fixture/toolkits":
                return (200, #"{"items":[{"slug":"github","name":"GitHub","enabled":true,"is_no_auth":false,"connected_account":{"status":"ACTIVE"}}],"next_cursor":null}"#)
            case "/api/v3.1/tool_router/session/trs_fixture/link":
                return (200, #"{"redirect_url":"https://connect.composio.dev/link/fixture","connected_account_id":"ca_fixture","link_token":"lt_fixture"}"#)
            default: XCTFail("Unexpected route"); return (404,"{}")
            }
        }
        let client = ComposioClient(key: "test-project-key", transport: transport)
        let session = try await client.create(userID: "device-unique-user", toolkits: ["github"])
        let toolkits = try await client.toolkits(sessionID: session.session_id)
        XCTAssertTrue(try XCTUnwrap(toolkits.first).connected)
        let link = try await client.link(sessionID: session.session_id, toolkit: "github")
        XCTAssertEqual(link.host, "connect.composio.dev")
    }
    func testRejectsCredentialRedirectAndRedactsServiceErrors() async {
        for url in ["http://connect.composio.dev/x", "https://composio.dev.evil.example/x", "https://user:secret@composio.dev/x", "https://composio.dev:8443/x"] { XCTAssertNil(ComposioClient.trustedURL(url)) }
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [ComposioMockProtocol.self]
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel(); ComposioMockProtocol.handler = nil }
        ComposioMockProtocol.handler = { _ in (401, "secret-project-key must not appear") }
        do { _ = try await ComposioClient(key: "secret-project-key", transport: transport).create(userID: "unique", toolkits: ["github"]); XCTFail("Must fail") }
        catch { XCTAssertFalse(error.localizedDescription.contains("secret-project-key")) }
    }
}
#endif
