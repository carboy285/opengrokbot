import Foundation
import PDFKit

/// A Bot's Knowledge folder: reference files (PDF, text, Markdown, CSV…) that it can search instead of needing them attached to every message.
enum KnowledgeSearch {
    static let textExtensions: Set<String> = ["txt", "md", "markdown", "csv", "tsv", "json", "log", "html", "htm", "xml", "yaml", "yml", "swift", "py", "js", "ts", "rtf"]
    static let maxFileBytes = 8_000_000
    static let maxFiles = 300

    struct Passage: Equatable { let file: String; let text: String }

    static func folder(for botDirectory: URL) -> URL { botDirectory.appendingPathComponent("Knowledge", isDirectory: true) }

    /// Copies files into the Knowledge folder. Returns how many were added.
    @discardableResult
    static func add(_ sources: [URL], to botDirectory: URL) throws -> Int {
        let destination = folder(for: botDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var added = 0
        for source in sources.prefix(50) {
            let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, (values.fileSize ?? 0) <= maxFileBytes else { continue }
            let ext = source.pathExtension.lowercased()
            guard ext == "pdf" || textExtensions.contains(ext) else { continue }
            var target = destination.appendingPathComponent(source.lastPathComponent)
            if FileManager.default.fileExists(atPath: target.path) { target = destination.appendingPathComponent(String(UUID().uuidString.prefix(6)) + "-" + source.lastPathComponent) }
            try FileManager.default.copyItem(at: source, to: target); added += 1
        }
        return added
    }

    static func files(in botDirectory: URL) -> [URL] {
        let root = folder(for: botDirectory)
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return [] }
        var found: [URL] = []
        for case let url as URL in walker where found.count < maxFiles {
            let ext = url.pathExtension.lowercased()
            guard ext == "pdf" || textExtensions.contains(ext), (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 <= maxFileBytes else { continue }
            found.append(url)
        }
        return found.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func text(of url: URL) -> String {
        if url.pathExtension.lowercased() == "pdf" { return PDFDocument(url: url)?.string ?? "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Splits text into passages of roughly `size` characters, on paragraph breaks where possible.
    static func passages(from text: String, file: String, size: Int = 500) -> [Passage] {
        var result: [Passage] = [], current = ""
        for paragraph in text.components(separatedBy: "\n\n") {
            let clean = paragraph.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard !clean.isEmpty else { continue }
            if current.count + clean.count + 1 > size, !current.isEmpty { result.append(Passage(file: file, text: current)); current = "" }
            if clean.count > size * 2 {
                var rest = Substring(clean)
                while rest.count > size { let cut = rest.prefix(size).lastIndex(of: " ") ?? rest.index(rest.startIndex, offsetBy: size); result.append(Passage(file: file, text: String(rest[..<cut]))); rest = rest[cut...].drop(while: { $0 == " " }) }
                current = String(rest)
            } else { current += (current.isEmpty ? "" : " ") + clean }
        }
        if !current.isEmpty { result.append(Passage(file: file, text: current)) }
        return result
    }

    /// Passages that contain the most of the query's words, best first.
    static func rank(_ passages: [Passage], query: String, limit: Int = 6) -> [Passage] {
        let words = Set(query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 2 })
        guard !words.isEmpty else { return [] }
        return passages.map { passage -> (Passage, Int) in
            let lower = passage.text.lowercased()
            return (passage, words.reduce(0) { $0 + (lower.contains($1) ? 1 + lower.components(separatedBy: $1).count - 2 : 0) })
        }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    /// The text a Bot receives for a search_knowledge request.
    static func search(query: String, in botDirectory: URL) -> String {
        let list = files(in: botDirectory)
        guard !list.isEmpty else { return "This Bot’s Knowledge folder is empty. The human can add files from the model menu → Add knowledge files." }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Knowledge files: " + list.map(\.lastPathComponent).joined(separator: ", ") }
        let all = list.flatMap { passages(from: text(of: $0), file: $0.lastPathComponent) }
        let best = rank(all, query: trimmed)
        guard !best.isEmpty else { return "No passages matched “\(trimmed)”. Files searched: " + list.map(\.lastPathComponent).joined(separator: ", ") }
        return best.map { "[\($0.file)] \($0.text)" }.joined(separator: "\n---\n")
    }
}
