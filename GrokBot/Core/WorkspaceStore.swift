import Foundation

struct WorkspaceStore {
    let url: URL
    var legacyURL: URL? = nil

    static var application: WorkspaceStore {
        #if DEBUG && os(macOS)
        if let directory = ProcessInfo.processInfo.environment["OPENGROKBOT_TEST_WORKSPACE_DIR"] ?? Self.testArgument("--opengrokbot-test-data") {
            return WorkspaceStore(url: URL(fileURLWithPath: directory).appendingPathComponent("workspace.json"))
        }
        #endif
        let directory = URL.applicationSupportDirectory.appending(path: "OpenGrokBot", directoryHint: .isDirectory)
        #if os(macOS)
        let legacy = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Containers/org.opengrokbot.mac/Data/Library/Application Support/OpenGrokBot/preview.json")
        return WorkspaceStore(url: directory.appending(path: "preview.json"), legacyURL: legacy)
        #else
        return WorkspaceStore(url: directory.appending(path: "preview.json"))
        #endif
    }

    #if DEBUG && os(macOS)
    static func testArgument(_ key: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: key), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
    #endif

    func load() throws -> Workspace? {
        if !FileManager.default.fileExists(atPath: url.path), let legacyURL,
           legacyURL != url, FileManager.default.fileExists(atPath: legacyURL.path) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: legacyURL, to: url)
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let original = try Data(contentsOf: url)
        var workspace = try JSONDecoder().decode(Workspace.self, from: original)
        if workspace.schemaVersion != 2 {
            let backup = url.deletingPathExtension().appendingPathExtension("legacy-backup.json")
            if !FileManager.default.fileExists(atPath: backup.path) { try original.write(to: backup, options: .atomic) }
            workspace.migrateLegacyDemo()
            try save(workspace)
        }
        return workspace
    }

    func save(_ workspace: Workspace) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoded = try JSONEncoder().encode(workspace)
        #if os(iOS)
        try encoded.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try encoded.write(to: url, options: .atomic)
        #endif
    }
}
