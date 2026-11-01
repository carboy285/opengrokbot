#if os(macOS)
import XCTest
@testable import GrokBotMac

final class MacRemoteHostTests: XCTestCase {
    @MainActor
    func testRealControllerPairsConfiguresSendsOnceAndObservesDesktopReply() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let suite = "org.opengrokbot.remote-test." + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName:suite))
        let secrets = KeychainSecretStore(service:suite)
        let app = AppModel(store:WorkspaceStore(url:root.appendingPathComponent("workspace.json")));app.enterPreview()
        let desktop = MacAppModel()
        let host = MacRemoteHost(port:48301,preferences:preferences,secrets:secrets)
        defer {
            host.stop();desktop.stopAll(immediately:true);try? secrets.delete(account:"pairing")
            preferences.removePersistentDomain(forName:suite)
            for bot in app.workspace.bots { try? FileManager.default.removeItem(at:desktop.workingDirectory(for:bot)) }
            try? FileManager.default.removeItem(at:root)
        }
        let executable = root.appendingPathComponent("fixture")
        try "#!/bin/sh\ncat >/dev/null\nprintf '%s\\n' '{\"type\":\"item.completed\",\"item\":{\"id\":\"reply\",\"type\":\"agent_message\",\"text\":\"Reply on the desktop\"}}'\n".write(to:executable,atomically:true,encoding:.utf8)
        try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:executable.path)
        desktop.installedCLIs=[InstalledCLI(provider:.codex,path:executable.path,version:"fixture")];desktop.selectedCLIID=desktop.installedCLIs[0].id
        host.mode = .wifi;host.address = "http://127.0.0.1:48301";host.attach(app:app,desktop:desktop);host.start()
        for _ in 0..<100 { if host.enabled { break };try await Task.sleep(for:.milliseconds(20)) }
        let pairing = try XCTUnwrap(host.pairing), client = RemoteHTTPClient()
        let first = try XCTUnwrap(try await client.snapshot(pairing,since:nil))
        XCTAssertEqual(first.workspace.bots.count,1);XCTAssertTrue(first.workspace.entries.isEmpty);XCTAssertTrue((first.workspace.sessions ?? [:]).isEmpty)
        XCTAssertNil(try await client.snapshot(pairing,since:first.revision))
        let bot = try XCTUnwrap(first.workspace.bots.first)
        let config = BotAIConfiguration(providers:[BotAIProvider(provider:.codex,model:"remote-model")],activeProvider:.codex)
        _ = try await client.fetch(pairing,path:"/v1/command",command:RemoteCommand(action:"configure_bot",botID:bot.id,configuration:config))
        let command = RemoteCommand(action:"send",botID:bot.id,text:"From my phone 🌎")
        _ = try await client.fetch(pairing,path:"/v1/command",command:command)
        _ = try await client.fetch(pairing,path:"/v1/command",command:command)
        for _ in 0..<100 { if app.entries(for:bot).last?.state == .complete { break };try await Task.sleep(for:.milliseconds(20)) }
        let result = try XCTUnwrap(try await client.snapshot(pairing,since:nil))
        XCTAssertEqual(result.workspace.entries.filter{$0.kind == .user}.count,1)
        XCTAssertEqual(result.workspace.entries.last?.text,"Reply on the desktop")
        XCTAssertEqual(app.workspace.bots.first?.aiConfiguration?.providers.first?.model,"remote-model")
        host.rotateKey()
        do { _ = try await client.snapshot(pairing,since:nil);XCTFail("Revoked pairing must be rejected") } catch { if case RemoteError.unauthorized = error {} else { XCTFail("Wrong error: \(error)") } }
        let refreshed = try XCTUnwrap(host.pairing)
        XCTAssertNotNil(try await client.snapshot(refreshed,since:nil))
    }
}
#endif
