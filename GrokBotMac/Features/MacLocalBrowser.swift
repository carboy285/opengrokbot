import AppKit
import SwiftUI
import WebKit

@MainActor
final class LocalBotBrowsers {
    static let shared = LocalBotBrowsers()
    private var sessions: [UUID:LocalBotBrowserSession] = [:]
    func open(_ bot: Bot, address: String? = nil) throws -> LocalBotBrowserSession {
        if let session = sessions[bot.id] { session.window?.makeKeyAndOrderFront(nil); if let address { try session.navigate(address) }; return session }
        guard sessions.count < 8 else { throw CloudError.message("Close a Bot browser before opening another. Up to eight browser windows can be open.") }
        let session = LocalBotBrowserSession(bot: bot)
        sessions[bot.id] = session
        session.closed = { [weak self] in self?.sessions[bot.id] = nil }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 780), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
        window.title = bot.name + " · Local browser"; window.isReleasedWhenClosed = false; window.delegate = session
        window.contentView = NSHostingView(rootView: LocalBotBrowserSurface(session: session)); session.window = window
        window.center(); window.makeKeyAndOrderFront(nil)
        try session.navigate(address ?? "https://duckduckgo.com")
        return session
    }
    func read(_ bot: Bot, address: String) async throws -> String { let session = try open(bot); return try await session.read(address) }
    func preview(_ bot: Bot) async throws -> RemoteBrowserPreview {
        guard let session = sessions[bot.id] else { return RemoteBrowserPreview(title: "Browser not open", url: "", imageData: nil) }
        let config = WKSnapshotConfiguration(); config.snapshotWidth = 900
        let image: NSImage = try await withCheckedThrowingContinuation { continuation in
            session.web.takeSnapshot(with: config) { image, error in
                if let image { continuation.resume(returning: image) } else { continuation.resume(throwing: error ?? CloudError.message("The browser preview is unavailable.")) }
            }
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor:0.6]), jpeg.count <= 2_000_000 else { throw CloudError.message("The browser preview is too large. Resize its window and retry.") }
        return RemoteBrowserPreview(title: session.web.title ?? bot.name, url: session.web.url?.absoluteString ?? "", imageData: jpeg)
    }
    func close(_ id: UUID) { sessions[id]?.window?.close() }
}

@MainActor
final class LocalBotBrowserSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    let web: WKWebView
    var window: NSWindow?
    var closed: (() -> Void)?
    @Published var address = ""
    @Published var feedback = "Local browser · this Bot’s private profile"
    @Published var back = false
    @Published var forward = false
    private var reader: CheckedContinuation<String,Error>?
    private var readerNavigation: WKNavigation?
    private var timeout: Task<Void,Never>?
    init(bot: Bot) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: bot.id)
        web = WKWebView(frame: .zero, configuration: configuration)
        super.init(); web.navigationDelegate = self; web.uiDelegate = self
    }
    static func allowed(_ url: URL?) -> Bool { guard let url else { return false }; return url.scheme == "https" && url.host != nil && url.user == nil && url.password == nil && url.absoluteString.count <= 4000 }
    func navigate(_ value: String, forReader: Bool = false) throws {
        guard let url = URL(string: value), Self.allowed(url) else { throw CloudError.message("Enter an HTTPS address without embedded credentials.") }
        if !forReader, reader != nil { finish(.failure(CloudError.message("The page was changed in the browser. Retry reading its new page."))) }
        let navigation = web.load(URLRequest(url: url)); if forReader { readerNavigation = navigation }; feedback = "Loading…"
    }
    func read(_ address: String) async throws -> String {
        guard reader == nil else { throw CloudError.message("This Bot’s browser is already reading a page.") }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                reader = continuation
                do { try navigate(address, forReader: true) } catch { finish(.failure(error)); return }
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(20)); try Task.checkCancellation(); self?.web.stopLoading(); self?.finish(.failure(CloudError.message("The local browser timed out. Its window stays open so you can inspect it or sign in, then retry."))) } catch {}
                }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.web.stopLoading(); self?.finish(.failure(CancellationError())) } }
    }
    private func finish(_ result: Result<String,Error>) { timeout?.cancel(); timeout = nil; let pending = reader; reader = nil; readerNavigation = nil; pending?.resume(with: result) }
    private func update() { address = web.url?.absoluteString ?? address; back = web.canGoBack; forward = web.canGoForward }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        update(); feedback = "Local browser · this Bot’s private profile"
        guard reader != nil, navigation === readerNavigation else { return }
        let script = "JSON.stringify({url:location.href,title:document.title,text:(document.body?.innerText||'').slice(0,16000),links:[...document.links].slice(0,25).map(a=>({text:a.innerText.slice(0,100),url:a.href}))})"
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let text = value as? String { self.finish(.success(text)) } else { self.finish(.failure(error ?? CloudError.message("This page could not be read."))) }
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { update(); feedback = "Page navigation failed. Retry or choose another page."; if navigation === readerNavigation { finish(.failure(error)) } }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { self.webView(webView, didFail: navigation, withError: error) }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(Self.allowed(navigationAction.request.url) ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if Self.allowed(navigationAction.request.url) { webView.load(navigationAction.request) }; return nil
    }
    func windowWillClose(_ notification: Notification) { web.stopLoading(); finish(.failure(CloudError.message("The Bot browser was closed."))); window?.contentView = nil; closed?(); closed = nil }
    func clearData() {
        let alert = NSAlert(); alert.messageText = "Clear this Bot’s browser cookies and login storage?"; alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Clear browser data")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        web.configuration.websiteDataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in self?.web.reload() }
    }
}

private struct BotWebSurface: NSViewRepresentable {
    let web: WKWebView
    func makeNSView(context: Context) -> WKWebView { web }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
private struct LocalBotBrowserSurface: View {
    @ObservedObject var session: LocalBotBrowserSession
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { session.web.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!session.back).help("Back")
                Button { session.web.goForward() } label: { Image(systemName: "chevron.right") }.disabled(!session.forward).help("Forward")
                Button { session.web.reload() } label: { Image(systemName: "arrow.clockwise") }.help("Reload")
                TextField("https://example.com", text: $session.address).textFieldStyle(.roundedBorder).onSubmit { navigate() }
                Button("Go") { navigate() }
                Button("Clear data") { session.clearData() }
            }.padding(10)
            Text(session.feedback).font(.caption).foregroundStyle(.secondary).padding(.bottom, 5)
            Divider(); BotWebSurface(web: session.web)
        }.frame(minWidth: 650, minHeight: 450)
    }
    private func navigate() { do { try session.navigate(session.address) } catch { session.feedback = error.localizedDescription } }
}
