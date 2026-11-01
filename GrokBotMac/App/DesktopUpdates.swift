import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class DesktopUpdates: ObservableObject {
    @Published private(set) var checking = false
    @Published private(set) var available = false
    @Published private(set) var version = ""
    @Published private(set) var message = "Check for a newer release. Your conversations stay on this Mac."
    @Published private(set) var releaseURL: URL?
    @Published private(set) var checkedAt: Date?
    var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.7.0" }
    private struct Release: Decodable { var tag_name: String; var html_url: String; var draft: Bool; var prerelease: Bool }
    func check(automatically: Bool = false) async {
        guard !checking else { return }
        let preferences = UserDefaults.standard
        if automatically {
            guard preferences.object(forKey: "checkAppUpdates") as? Bool ?? true,
                  Date().timeIntervalSince1970 - preferences.double(forKey: "lastAppUpdateCheck") > 86400 else { return }
        }
        checking = true; defer { checking = false }
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/carboy285/opengrokbot/releases?per_page=20")!)
            request.timeoutInterval = 15; request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count < 2_000_000 else { throw URLError(.badServerResponse) }
            let releases = try JSONDecoder().decode([Release].self, from: data)
                .filter { !$0.draft && Self.numbers($0.tag_name) != nil && Self.trusted($0.html_url) }
                .sorted { Self.newer($0.tag_name, than: $1.tag_name) }
            checkedAt = Date(); preferences.set(Date().timeIntervalSince1970, forKey: "lastAppUpdateCheck")
            if let release = releases.first {
                available = Self.newer(release.tag_name, than: current); version = release.tag_name
                releaseURL = URL(string: release.html_url)
                message = available ? "\(release.tag_name) is available\(release.prerelease ? " as a development release" : "")." : "You’re using \(current). No newer version is published."
            } else { available = false; message = "No downloadable releases have been published yet." }
        } catch { message = "Updates could not be reached. Check your internet connection and try again." }
    }
    func openDownload() {
        guard let url = releaseURL, Self.trusted(url.absoluteString) else { return }
        NSWorkspace.shared.open(url)
    }
    private static func trusted(_ value: String) -> Bool {
        guard let url = URL(string: value) else { return false }
        return url.scheme == "https" && url.host == "github.com" && url.user == nil && url.password == nil && url.path.hasPrefix("/carboy285/opengrokbot/releases/")
    }
    private static func numbers(_ value: String) -> [Int]? {
        let clean = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let core = clean.split(whereSeparator: { $0 == "-" || $0 == "+" }).first ?? ""
        let parts = core.split(separator: ".").compactMap { Int($0) }
        return parts.count == 3 ? parts : nil
    }
    private static func newer(_ lhs: String, than rhs: String) -> Bool {
        guard let a = numbers(lhs), let b = numbers(rhs) else { return false }
        return b.lexicographicallyPrecedes(a)
    }
}

struct DesktopUpdatesView: View {
    @ObservedObject var updates: DesktopUpdates
    @AppStorage("checkAppUpdates") private var automatic = true
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("OpenGrokBot \(updates.current)", systemImage: "arrow.down.circle").font(.title2)
            Text(updates.message).foregroundStyle(.secondary)
            Toggle("Notify me about updates once a day when the app is open", isOn: $automatic)
            HStack {
                Button(updates.checking ? "Checking…" : "Check for updates") { Task { await updates.check() } }.disabled(updates.checking)
                if updates.available { Button("Open download page") { updates.openDownload() }.buttonStyle(.borderedProminent) }
            }
            if let date = updates.checkedAt { Text("Last checked \(date.formatted())").font(.caption).foregroundStyle(.secondary) }
            Text("Install the new build using the same app location. Your saved workspace is kept. Updates are downloaded from this project’s GitHub releases.").font(.footnote).foregroundStyle(.secondary)
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 18))
    }
}
