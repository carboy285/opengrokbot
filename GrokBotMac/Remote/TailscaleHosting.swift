import Foundation

enum TailscaleHosting {
    static let httpsPort = 8443
    static var executable: String? {
        let candidates = CLIInstallationScanner.environment["PATH", default: ""].split(separator: ":").map { String($0) + "/tailscale" } + ["/Applications/Tailscale.app/Contents/MacOS/Tailscale"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    static func configure(localPort: UInt16, funnel: Bool) -> String? {
        guard let path = executable else { return nil }
        let result = CLIInstallationScanner.capture(path: path, arguments: ["status","--json"], timeout: 10, limit: 65536)
        guard result.exit == 0, let object = object(result.text), let info = object["Self"] as? [String:Any],
              let raw = info["DNSName"] as? String else { return nil }
        let host = raw.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard host.hasSuffix(".ts.net"), host.range(of: "^[a-zA-Z0-9.-]+$", options: .regularExpression) != nil,
              let config = status(path), available(config, host: host, port: localPort) else { return nil }
        let command = CLIInstallationScanner.capture(path: path, arguments: [funnel ? "funnel" : "serve", "--bg", "--https=8443", "http://127.0.0.1:\(localPort)"], timeout: 15, limit: 8192)
        guard command.exit == 0, let updated = status(path), proxy(updated, host: host) == "http://127.0.0.1:\(localPort)" else { return nil }
        let allowed = (updated["AllowFunnel"] as? [String:Bool])?[host + ":8443"] == true
        guard allowed == funnel else { return nil }
        return "https://\(host):8443"
    }
    static func remove(localPort: UInt16, address: String, funnel: Bool) -> Bool {
        guard let path = executable, let host = URL(string: address)?.host, let current = status(path) else { return false }
        guard proxy(current, host: host) == "http://127.0.0.1:\(localPort)" else { return true }
        return CLIInstallationScanner.capture(path: path, arguments: [funnel ? "funnel" : "serve", "--https=8443", "off"], timeout: 10).exit == 0
    }
    private static func status(_ path: String) -> [String:Any]? {
        let value = CLIInstallationScanner.capture(path: path, arguments: ["serve","status","--json"], timeout: 10, limit: 65536)
        return value.exit == 0 ? object(value.text) : nil
    }
    private static func object(_ text: String) -> [String:Any]? { text.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String:Any] } }
    private static func proxy(_ config: [String:Any], host: String) -> String? {
        let web = config["Web"] as? [String:Any], server = web?[host + ":8443"] as? [String:Any]
        let handlers = server?["Handlers"] as? [String:Any], root = handlers?["/"] as? [String:Any]
        return root?["Proxy"] as? String
    }
    private static func available(_ config: [String:Any], host: String, port: UInt16) -> Bool {
        let tcp = config["TCP"] as? [String:Any]
        guard tcp?["8443"] != nil else { return true }
        return proxy(config, host: host) == "http://127.0.0.1:\(port)"
    }
}
