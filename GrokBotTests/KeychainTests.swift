import XCTest
#if os(macOS)
@testable import GrokBotMac
#else
@testable import GrokBot
#endif

final class KeychainTests: XCTestCase {
    func testSaveReplaceReadDelete() throws {
        let store = KeychainSecretStore(service: "OpenGrokBot.Tests.\(UUID().uuidString)")
        defer { try? store.delete(account: "test") }
        XCTAssertNil(try store.read(account: "test"))
        try store.save(Data("first".utf8), account: "test")
        try store.save(Data("replacement".utf8), account: "test")
        XCTAssertEqual(try store.read(account: "test"), Data("replacement".utf8))
        try store.delete(account: "test")
        try store.delete(account: "test")
        XCTAssertNil(try store.read(account: "test"))
    }
}
