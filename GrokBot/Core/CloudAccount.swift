import Foundation
import Combine
import CryptoKit
import AuthenticationServices
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Supabase Auth + authenticated, encrypted, short-lived device mailbox.
@MainActor
final class CloudAccount: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var session: CloudSession?
    @Published private(set) var devices: [CloudDevice] = []
    @Published private(set) var identity: CloudIdentity?
    @Published private(set) var providers: Set<String> = []
    @Published var busy = false
    @Published var notice: String?
    @Published var error: String?
    let kind: String
    private let secrets: KeychainSecretStore
    private let network: URLSession
    private var browser: ASWebAuthenticationSession?
    private weak var authenticationSource: CloudAccount?
    private var authenticationSubscription: AnyCancellable?
    private var authCompletion: AuthCompletion?
    private var refreshTask: Task<CloudSession, Error>?
    private var generation = UUID()
    private var approvals: [String:String] = [:]
    private var pinnedHosts: [String:String] = [:]
    var signedIn: Bool { session != nil }
    var email: String { session?.user.email ?? "Account" }
    var localDevice: CloudDevice? { devices.first { $0.id == identity?.id } }
    var controllers: [CloudDevice] { devices.filter { $0.kind == "controller" } }
    var hosts: [CloudDevice] { devices.filter { $0.kind == "host" } }

    init(kind: String, secrets: KeychainSecretStore? = nil, configuration: URLSessionConfiguration = .ephemeral) {
        self.kind = kind; self.secrets = secrets ?? KeychainSecretStore(service: "org.opengrokbot.cloud." + kind)
        configuration.httpCookieStorage = nil; configuration.urlCache = nil; configuration.timeoutIntervalForRequest = 20; configuration.timeoutIntervalForResource = 30
        network = URLSession(configuration: configuration, delegate: CloudNetworkDelegate(), delegateQueue: nil); super.init()
        do {
            if let data = try self.secrets.read(account: "session") { session = try JSONDecoder().decode(CloudSession.self, from: data) }
            if let session { try loadIdentity(owner: session.user.id) }
        } catch { self.error = "Unlock this device’s Keychain to restore sign-in."; session = nil }
    }
    /// Desktop controllers use their own encryption identity but one shared auth refresher.
    func useAccount(from source: CloudAccount) {
        guard authenticationSource !== source else { return }
        authenticationSource = source
        authenticationSubscription = source.$session.sink { [weak self] session in
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    if self.session?.user.id != session?.user.id || self.identity == nil {
                        self.generation = UUID(); self.devices = []; self.identity = nil; self.approvals = [:]; self.pinnedHosts = [:]
                        if let session { try self.loadIdentity(owner: session.user.id) }
                    }
                    self.session = session
                } catch { self.session = nil; self.error = "Unlock Keychain to load this controller's identity." }
            }
        }
    }
    private func loadIdentity(owner: UUID) throws {
        let account = "identity-" + owner.uuidString
        let next: CloudIdentity
        if let data = try secrets.read(account: account) { next = try JSONDecoder().decode(CloudIdentity.self, from: data) }
        else { next = CloudIdentity(); try secrets.save(JSONEncoder().encode(next), account: account) }
        let nextApprovals = try readPins("approved-" + owner.uuidString)
        let nextHosts = try readPins("hosts-" + owner.uuidString)
        _ = try next.publicKey
        identity = next; approvals = nextApprovals; pinnedHosts = nextHosts
    }
    private func readPins(_ key: String) throws -> [String:String] { if let data = try secrets.read(account: key) { return try JSONDecoder().decode([String:String].self, from: data) }; return [:] }
    private func save(_ session: CloudSession) throws {
        var value = session; value.setExpiry()
        let changed = self.session?.user.id != value.user.id
        let previousIdentity = identity, previousApprovals = approvals, previousHosts = pinnedHosts
        do {
            if changed || identity == nil { try loadIdentity(owner: value.user.id) }
            try secrets.save(JSONEncoder().encode(value), account: "session")
        } catch {
            identity = previousIdentity; approvals = previousApprovals; pinnedHosts = previousHosts
            throw error
        }
        if changed { generation = UUID(); refreshTask?.cancel(); refreshTask = nil; devices = [] }
        self.session = value
    }
    func signIn(email: String, password: String, create: Bool) async {
        guard !busy else { return }; busy = true; error = nil; notice = nil; defer { busy = false }
        let epoch = generation
        do {
            let data = try await request(path: create ? "/auth/v1/signup?redirect_to=opengrokbot%3A%2F%2Fauth%2Fcallback" : "/auth/v1/token?grant_type=password", body: ["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password], authenticated: false)
            guard epoch == generation else { return }
            if let value = try? JSONDecoder().decode(CloudSession.self, from: data) { try save(value) }
            else if create { notice = "Check your email to confirm your account, then return here and sign in." }
            else { throw CloudError.message("Sign-in did not return a session. Try again.") }
        } catch { if epoch == generation { self.error = error.localizedDescription } }
    }
    func resetPassword(email: String) async {
        guard !busy, !email.isEmpty else { return }; busy = true; defer { busy = false }
        do { _ = try await request(path: "/auth/v1/recover?redirect_to=\(CloudConfiguration.callback)", body: ["email":email], authenticated:false); notice = "If an account exists, Supabase will email a recovery link." }
        catch { self.error = error.localizedDescription }
    }
    func loadProviders() async {
        guard let data = try? await request(path:"/auth/v1/settings", method:"GET", authenticated:false), let settings = try? JSONSerialization.jsonObject(with:data) as? [String:Any], let external = settings["external"] as? [String:Bool] else { return }
        providers = Set(external.filter { $0.value }.map(\.key))
    }
    func oauth(_ provider: String) async {
        guard ["google","github"].contains(provider), !busy else { return }; busy = true; error = nil; defer { busy = false; browser = nil; authCompletion = nil }
        let epoch = generation
        do {
            let verifier = UUID().uuidString + UUID().uuidString
            let challenge = Data(SHA256.hash(data:Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
            guard var parts = URLComponents(url: CloudConfiguration.url.appendingPathComponent("auth/v1/authorize"), resolvingAgainstBaseURL:false) else { throw CloudError.invalidPacket }
            parts.queryItems = [URLQueryItem(name:"provider",value:provider),URLQueryItem(name:"redirect_to",value:CloudConfiguration.callback),URLQueryItem(name:"code_challenge",value:challenge),URLQueryItem(name:"code_challenge_method",value:"s256")]
            guard let authorizeURL = parts.url else { throw CloudError.invalidPacket }
            let callback: URL = try await withCheckedThrowingContinuation { continuation in
                let completion = AuthCompletion(continuation); authCompletion = completion
                let web = ASWebAuthenticationSession(url: authorizeURL, callbackURLScheme: "opengrokbot") { url, error in
                    Task { @MainActor in
                        if let url { completion.finish(.success(url)) }
                        else { completion.finish(.failure(error ?? CloudError.signedOut)) }
                    }
                }
                web.presentationContextProvider = self; web.prefersEphemeralWebBrowserSession = true; browser = web
                if !web.start() { completion.finish(.failure(CloudError.message("Could not open the sign-in browser."))) }
            }
            guard epoch == generation else { return }
            let result = URLComponents(url:callback,resolvingAgainstBaseURL:false)
            guard callback.host == "auth", callback.path == "/callback", let code = result?.queryItems?.first(where:{$0.name == "code"})?.value else { throw CloudError.message("Sign-in was cancelled or the provider is not configured.") }
            let data = try await request(path:"/auth/v1/token?grant_type=pkce",body:["auth_code":code,"code_verifier":verifier],authenticated:false)
            guard epoch == generation else { return }
            try save(JSONDecoder().decode(CloudSession.self,from:data))
        } catch { if epoch == generation { self.error = error.localizedDescription } }
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? NSWindow()
        #else
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? UIWindow()
        #endif
    }
    func signOut() async {
        let oldSession = session
        browser?.cancel(); authCompletion?.finish(.failure(CloudError.signedOut))
        // Clear local state immediately, even if the network is unavailable.
        generation = UUID(); refreshTask?.cancel(); refreshTask = nil; session = nil; identity = nil; devices = []; approvals = [:]; pinnedHosts = [:]
        do { try secrets.delete(account:"session") } catch { self.error = "Keychain sign-out failed. Unlock this device and sign out again." }
        if let oldSession { _ = try? await raw(path:"/auth/v1/logout?scope=local",method:"POST",data:Data("{}".utf8),token:oldSession.access_token) }
    }
    private func accessToken() async throws -> String {
        guard let current = session else { throw CloudError.signedOut }
        if (current.expires_at ?? 0) > Date().timeIntervalSince1970 + 90 { return current.access_token }
        if let refreshTask { return try await refreshTask.value.access_token }
        let epoch = generation
        let task = Task { @MainActor in
            let data = try await raw(path:"/auth/v1/token?grant_type=refresh_token",method:"POST",data:JSONEncoder().encode(["refresh_token":current.refresh_token]),token:nil)
            let refreshed = try JSONDecoder().decode(CloudSession.self,from:data)
            guard epoch == generation, session?.user.id == current.user.id else { throw CloudError.signedOut }
            try save(refreshed); return refreshed
        }
        refreshTask = task; defer { refreshTask = nil }
        return try await task.value.access_token
    }
    func request(path: String, method: String = "POST", body: [String:String]? = nil, authenticated: Bool = true) async throws -> Data {
        let epoch = generation
        if authenticated, let source = authenticationSource {
            guard source.session?.user.id == session?.user.id, session != nil else { throw CloudError.signedOut }
            let result = try await source.request(path: path, method: method, body: body)
            guard epoch == generation else { throw CloudError.signedOut }
            return result
        }
        let token = authenticated ? try await accessToken() : nil
        let result = try await raw(path:path,method:method,data:try body.map { try JSONEncoder().encode($0) },token:token)
        if authenticated, epoch != generation { throw CloudError.signedOut }
        return result
    }
    private func raw(path: String, method: String, data: Data?, token: String?) async throws -> Data {
        guard let url = URL(string:path,relativeTo:CloudConfiguration.url), url.scheme == "https", url.host == CloudConfiguration.url.host else { throw CloudError.invalidPacket }
        var request = URLRequest(url:url); request.httpMethod = method; request.httpBody = data
        request.setValue(CloudConfiguration.publishableKey,forHTTPHeaderField:"apikey")
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        if let token { request.setValue("Bearer " + token,forHTTPHeaderField:"Authorization") }
        let (result,response) = try await network.data(for:request)
        guard let response = response as? HTTPURLResponse, result.count <= 16_000_000 else { throw CloudError.invalidPacket }
        guard (200...299).contains(response.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with:result)) as? [String:Any]
            let text = object?["msg"] as? String ?? object?["message"] as? String ?? object?["error_description"] as? String ?? "Account service is unavailable. Try again."
            throw CloudError.message(String(text.prefix(400)))
        }; return result
    }
    func sync(available: Bool = true) async throws {
        guard let identity else { throw CloudError.signedOut }
        #if os(macOS)
        let name = (Host.current().localizedName ?? "Mac") + (kind == "controller" ? " · remote view" : "")
        #else
        let name = UIDevice.current.name
        #endif
        _ = try await request(path:"/rest/v1/rpc/opengrok_register_device",body:["device_id":identity.id.uuidString,"device_name":name,"device_kind":kind,"device_key":try identity.publicKey,"is_available":available ? "true":"false"])
        let data = try await request(path:"/rest/v1/opengrok_devices?select=id,name,kind,public_key,last_seen,available&order=last_seen.desc",method:"GET")
        devices = try CloudCoding.decoder().decode([CloudDevice].self,from:data)
    }
    func botPins(host: UUID) async throws -> [CloudBotPin] {
        let data = try await request(path: "/rest/v1/opengrok_bot_pins?select=bot_id,is_pinned&host_id=eq." + host.uuidString, method: "GET")
        return try JSONDecoder().decode([CloudBotPin].self, from: data)
    }
    @discardableResult
    func setBotPin(host: UUID, bot: UUID, pinned: Bool, onlyIfMissing: Bool = false) async throws -> CloudBotPin {
        let data = try await request(path: "/rest/v1/rpc/opengrok_set_bot_pin", body: ["host_device": host.uuidString, "bot": bot.uuidString, "pinned": String(pinned), "only_if_missing": String(onlyIfMissing)])
        guard let pin = try JSONDecoder().decode([CloudBotPin].self, from: data).first else { throw CloudError.invalidPacket }
        return pin
    }
    func approved(_ device: CloudDevice) -> Bool { approvals[device.id.uuidString] == device.public_key }
    func approve(_ device: CloudDevice, allowed: Bool) throws {
        guard let owner = session?.user.id, device.kind == "controller" else { throw CloudError.signedOut }
        var next = approvals; next[device.id.uuidString] = allowed ? device.public_key : nil
        try secrets.save(JSONEncoder().encode(next),account:"approved-" + owner.uuidString); approvals = next
    }
    func pin(_ device: CloudDevice) throws {
        guard let owner = session?.user.id else { throw CloudError.signedOut }
        if let old = pinnedHosts[device.id.uuidString], old != device.public_key { throw CloudError.message("The desktop’s identity changed. Sign out and verify the desktop before reconnecting.") }
        if pinnedHosts[device.id.uuidString] == device.public_key { return }
        var next = pinnedHosts; next[device.id.uuidString] = device.public_key
        try secrets.save(JSONEncoder().encode(next),account:"hosts-" + owner.uuidString); pinnedHosts = next
    }
    func send(_ data: Data, to peer: CloudDevice, id: UUID, kind: String) async throws {
        guard let identity, let owner = session?.user.id else { throw CloudError.signedOut }
        let packet = try identity.seal(data,to:peer,owner:owner,id:id,kind:kind)
        _ = try await request(path:"/rest/v1/rpc/opengrok_send",body:["packet_id":id.uuidString,"from_device":identity.id.uuidString,"to_device":peer.id.uuidString,"packet_kind":kind,"payload":packet.ciphertext])
    }
    func poll() async throws -> [CloudPacket] {
        guard let identity else { throw CloudError.signedOut }
        let data = try await request(path:"/rest/v1/rpc/opengrok_poll",body:["device_id":identity.id.uuidString])
        return try CloudCoding.decoder().decode([CloudPacket].self,from:data)
    }
    func acknowledge(_ packet: CloudPacket) async throws {
        guard let identity else { throw CloudError.signedOut }
        _ = try await request(path:"/rest/v1/rpc/opengrok_ack",body:["device_id":identity.id.uuidString,"packet_id":packet.id.uuidString,"packet_kind":packet.kind])
    }
    func decrypt(_ packet: CloudPacket, peer: CloudDevice) throws -> Data {
        guard let identity, let owner = session?.user.id else { throw CloudError.signedOut }
        return try identity.open(packet,from:peer,owner:owner)
    }
}

private final class CloudNetworkDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor
private final class AuthCompletion {
    private var continuation: CheckedContinuation<URL, Error>?
    init(_ continuation: CheckedContinuation<URL, Error>) { self.continuation = continuation }
    func finish(_ result: Result<URL, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}
