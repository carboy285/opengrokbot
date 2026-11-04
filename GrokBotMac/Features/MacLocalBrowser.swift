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
    func read(_ bot: Bot, address: String, directory: URL) async throws -> String { let session = try open(bot); return try await session.read(address, directory: directory) }
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
    private var readDirectory: URL?
    private var timedOut = false
    private var readerAddress = ""
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
    func read(_ address: String, directory: URL) async throws -> String {
        guard reader == nil else { throw CloudError.message("This Bot’s browser is already reading a page.") }
        readDirectory = directory; timedOut = false; readerAddress = address
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                reader = continuation
                do { try navigate(address, forReader: true) } catch { finish(.failure(error)); return }
                // A slow page is not a failure: after 45 seconds, stop loading and hand back whatever has rendered so far.
                timeout = Task { [weak self] in
                    do {
                        try await Task.sleep(for: .seconds(45)); try Task.checkCancellation()
                        guard let self, self.reader != nil else { return }
                        self.timedOut = true; self.web.stopLoading()
                        await self.completeRead(note: "The page was slow to load, so this is what had loaded when I stopped waiting. If something is missing, try another page or approach.")
                    } catch {}
                }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.web.stopLoading(); self?.finish(.failure(CancellationError())) } }
    }

    // MARK: Secure login
    private static let fillScript = """
    const visible = el => { const r = el.getBoundingClientRect(); const s = getComputedStyle(el); return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none' && !el.disabled && !el.readOnly; };
    const setValue = (el, value) => { const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set; el.focus(); setter.call(el, value); el.dispatchEvent(new Event('input', {bubbles: true})); el.dispatchEvent(new Event('change', {bubbles: true})); };
    const all = [...document.querySelectorAll('input')].filter(visible);
    const password = all.find(el => el.type === 'password');
    const inputs = password && password.form ? all.filter(el => el.form === password.form) : all;
    const hint = el => ((el.name || '') + ' ' + (el.id || '') + ' ' + (el.autocomplete || '') + ' ' + (el.placeholder || '') + ' ' + (el.getAttribute('aria-label') || '')).toLowerCase();
    const userField = inputs.find(el => ['text', 'email', 'tel'].includes(el.type) && /user|email|login|account|name/.test(hint(el))) || inputs.find(el => ['text', 'email'].includes(el.type));
    const submit = field => {
      const form = field.closest('form');
      const scope = form || document;
      const button = scope.querySelector('button[type=submit], input[type=submit]') || [...scope.querySelectorAll('button, [role=button]')].find(b => visible(b) && /sign in|log in|login|continue|next|submit/i.test(b.innerText || b.value || ''));
      if (button) { button.click(); return true; }
      if (form && form.requestSubmit) { form.requestSubmit(); return true; }
      return false;
    };
    if (password) { if (userField && !userField.value) setValue(userField, u); setValue(password, p); return submit(password) ? 'submitted' : 'filled'; }
    if (userField) { setValue(userField, u); return submit(userField) ? 'username-submitted' : 'username-filled'; }
    return 'no-form';
    """

    private func waitUntilLoaded(timeout: Double) async throws {
        try await Task.sleep(for: .milliseconds(400))
        let deadline = Date().addingTimeInterval(timeout)
        while web.isLoading, Date() < deadline { try await Task.sleep(for: .milliseconds(250)) }
    }

    /// Opens the page and types a saved login into it. The credentials go straight into the page from this process: they are
    /// never returned, logged, or added to a transcript. Fills only on `loginHost` (or a subdomain), re-checked after every redirect.
    func fillLogin(url: String, loginHost: String, username: String, password: String) async throws -> String {
        guard reader == nil else { throw CloudError.message("This Bot’s browser is reading a page. Try again in a moment.") }
        try navigate(url)
        try await waitUntilLoaded(timeout: 20)
        var step = "no-form"
        for attempt in 0..<3 {
            guard let current = web.url?.host, SecureLoginStore.matches(loginHost: loginHost, pageHost: current) else {
                throw CloudError.message("The page moved to \(web.url?.host ?? "another site"), which is not the site this login was saved for. Nothing was filled in.")
            }
            let value = try await web.callAsyncJavaScript(Self.fillScript, arguments: ["u": username, "p": password], in: nil, contentWorld: .page)
            step = (value as? String) ?? "no-form"
            guard step == "username-submitted", attempt < 2 else { break }
            try await Task.sleep(for: .seconds(3))
            try await waitUntilLoaded(timeout: 10)
        }
        switch step {
        case "submitted": return "Entered the saved username and password for \(loginHost) and submitted the form. Read the page to see whether sign-in worked; a verification code may still be needed."
        case "username-submitted": return "Entered the username for \(loginHost) and continued, but no password step appeared. Read the page to see where it stopped."
        case "filled", "username-filled": return "Filled in the login fields for \(loginHost) but found no button to submit. Ask the user to press the sign-in button in the Bot browser."
        default: return "No login form was found on the page."
        }
    }

    private func finish(_ result: Result<String,Error>) { timeout?.cancel(); timeout = nil; let pending = reader; reader = nil; readerNavigation = nil; pending?.resume(with: result) }
    private func update() { address = web.url?.absoluteString ?? address; back = web.canGoBack; forward = web.canGoForward }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        update(); feedback = "Local browser · this Bot’s private profile"
        guard reader != nil, navigation === readerNavigation else { return }
        readerNavigation = nil
        Task { [weak self] in await self?.completeRead() }
    }
    private static let readScript = "JSON.stringify({url:location.href,title:document.title,text:(document.body?.innerText||'').slice(0,16000),links:[...document.links].slice(0,25).map(a=>({text:a.innerText.slice(0,100),url:a.href}))})"
    /// Dynamic pages (fantasy draft rooms, dashboards) keep rendering after the load event: wait until loading stops and the text length is steady.
    private func settle() async {
        var previous: String?; var stable = 0; let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, reader != nil {
            let state = try? await web.evaluateJavaScript("document.readyState+'|'+(document.body?.innerText||'').length") as? String
            let ready = !web.isLoading && (state?.hasPrefix("complete|") ?? false)
            stable = ready && state == previous ? stable + 1 : 0; previous = state
            if stable >= 2 { return }
            try? await Task.sleep(for: .milliseconds(300))
        }
    }
    private func completeRead(note: String? = nil) async {
        await settle()
        guard reader != nil else { return }
        guard let raw = try? await web.evaluateJavaScript(Self.readScript) as? String else { finish(.failure(CloudError.message("This page could not be read."))); return }
        guard reader != nil else { return }
        var page = (raw.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String:Any] ?? [:]
        guard !page.isEmpty else { finish(.success(raw)); return }
        if let note { page["loadNote"] = note }
        switch await captureScreenshot() {
        case .success(let path):
            page["screenshot"] = path
            page["screenshotNote"] = "A screenshot of the page exactly as rendered (layout, images, charts, scores, canvas content that text extraction misses). Open this image file with your file or image viewing tool and use it together with the text."
        case .failure(let error): page["screenshotError"] = (error as? CloudError)?.errorDescription ?? "The screenshot could not be captured."
        }
        guard reader != nil else { return }
        let data = try? JSONSerialization.data(withJSONObject: page, options: [.withoutEscapingSlashes])
        finish(.success(data.flatMap { String(data: $0, encoding: .utf8) } ?? raw))
    }
    /// Saves a JPEG of the rendered page as <Bot folder>/Attachments/<uuid>-Page.jpg and keeps only the newest twelve.
    private func captureScreenshot() async -> Result<String,Error> {
        guard let directory = readDirectory else { return .failure(CloudError.message("Screenshots are unavailable.")) }
        let config = WKSnapshotConfiguration(); config.snapshotWidth = 1400
        guard let image = try? await web.takeSnapshot(configuration: config), let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]), jpeg.count <= 20_000_000 else { return .failure(CloudError.message("The screenshot could not be captured. Make sure the browser window is not minimized.")) }
        let folder = directory.appendingPathComponent("Attachments", isDirectory: true)
        let name = UUID().uuidString.lowercased() + "-Page.jpg"
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try jpeg.write(to: folder.appendingPathComponent(name), options: .atomic)
            let old = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []).filter { $0.lastPathComponent.hasSuffix("-Page.jpg") && $0.lastPathComponent != name }
                .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
            for url in old.dropFirst(11) { try? FileManager.default.removeItem(at: url) }
            return .success("Attachments/" + name)
        } catch { return .failure(CloudError.message("The screenshot could not be saved.")) }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        update(); feedback = "Page navigation failed. Retry or choose another page."
        guard navigation === readerNavigation, !timedOut else { return }
        // Tell the Bot exactly what went wrong so it can try another way, rather than ending its turn.
        let page: [String: Any] = ["url": web.url?.absoluteString ?? readerAddress, "title": "", "text": "", "links": [], "loadError": (error as NSError).localizedDescription]
        finish(.success((try? JSONSerialization.data(withJSONObject: page, options: [.withoutEscapingSlashes])).flatMap { String(data: $0, encoding: .utf8) } ?? "{\"loadError\":\"The page could not be loaded.\"}"))
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { self.webView(webView, didFail: navigation, withError: error) }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(Self.allowed(navigationAction.request.url) && !navigationAction.shouldPerformDownload ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(.deny) }
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
