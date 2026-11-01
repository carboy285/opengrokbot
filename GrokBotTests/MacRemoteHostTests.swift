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
        let host = MacRemoteHost(preferences:preferences,account:CloudAccount(kind:"host",secrets:secrets))
        defer {
            host.stop();desktop.stopAll(immediately:true);try? secrets.delete(account:"session")
            preferences.removePersistentDomain(forName:suite)
            for bot in app.workspace.bots { try? FileManager.default.removeItem(at:desktop.workingDirectory(for:bot)) }
            try? FileManager.default.removeItem(at:root)
        }
        let executable = root.appendingPathComponent("fixture")
        try "#!/bin/sh\ncat >/dev/null\nprintf '%s\\n' '{\"type\":\"item.completed\",\"item\":{\"id\":\"reply\",\"type\":\"agent_message\",\"text\":\"Reply on the desktop\"}}'\n".write(to:executable,atomically:true,encoding:.utf8)
        try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:executable.path)
        desktop.installedCLIs=[InstalledCLI(provider:.codex,path:executable.path,version:"fixture")];desktop.selectedCLIID=desktop.installedCLIs[0].id
        host.attach(app:app,desktop:desktop)
        func call(_ command: RemoteCommand? = nil, target: String = "/v1/state") async throws -> RemoteHostResponse {
            await host.dispatch(RemoteHostRequest(method:command == nil ? "GET":"POST",target:command == nil ? target:"/v1/command",body:try command.map { try JSONEncoder().encode($0) } ?? Data()))
        }
        let first = try CloudCoding.decoder().decode(RemoteSnapshot.self,from:await call().body)
        XCTAssertEqual(first.workspace.bots.count,1);XCTAssertTrue(first.workspace.entries.isEmpty);XCTAssertTrue((first.workspace.sessions ?? [:]).isEmpty)
        let unchanged = try await call(target:"/v1/state?since=" + first.revision)
        XCTAssertEqual(unchanged.status,204)
        let bot = try XCTUnwrap(first.workspace.bots.first)
        let config = BotAIConfiguration(providers:[BotAIProvider(provider:.codex,model:"remote-model")],activeProvider:.codex)
        _ = try await call(RemoteCommand(action:"configure_bot",botID:bot.id,configuration:config))
        let command = RemoteCommand(action:"send",botID:bot.id,text:"From my phone 🌎")
        _ = try await call(command)
        _ = try await call(command)
        for _ in 0..<100 { if app.entries(for:bot).last?.state == .complete { break };try await Task.sleep(for:.milliseconds(20)) }
        let result = try CloudCoding.decoder().decode(RemoteSnapshot.self,from:await call().body)
        XCTAssertEqual(result.workspace.entries.filter{$0.kind == .user}.count,1)
        XCTAssertEqual(result.workspace.entries.last?.text,"Reply on the desktop")
        XCTAssertEqual(app.workspace.bots.first?.aiConfiguration?.providers.first?.model,"remote-model")
    }
}
#endif
