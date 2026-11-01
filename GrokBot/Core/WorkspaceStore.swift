import Foundation

struct WorkspaceStore {
    let url: URL

    static var application: WorkspaceStore {
        let directory = URL.applicationSupportDirectory.appending(path: "OpenGrokBot", directoryHint: .isDirectory)
        return WorkspaceStore(url: directory.appending(path: "preview.json"))
    }

    func load() throws -> Workspace? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Workspace.self, from: Data(contentsOf: url))
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
