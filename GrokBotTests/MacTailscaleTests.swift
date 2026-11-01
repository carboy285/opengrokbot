#if os(macOS)
import XCTest
@testable import GrokBotMac

final class MacTailscaleTests: XCTestCase {
    func testTailscaleNeverReplacesOrRemovesAnotherService() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let script=root.appendingPathComponent("tailscale"),state=root.appendingPathComponent("state.json"),after=root.appendingPathComponent("after.json"),log=root.appendingPathComponent("commands.txt")
        let host="desktop.example.ts.net"
        func configuration(_ handlers:[String:Any],funnel:Bool=false) -> [String:Any] { ["TCP":["8443":["HTTPS":true]],"Web":[host+":8443":["Handlers":handlers]],"AllowFunnel":[host+":8443":funnel]] }
        func write(_ value:[String:Any],to url:URL) throws { try JSONSerialization.data(withJSONObject:value).write(to:url) }
        let code="""
        #!/bin/sh
        if [ "$1" = "status" ]; then printf '%s\\n' '{"Self":{"DNSName":"desktop.example.ts.net."}}'; exit 0; fi
        if [ "$2" = "status" ]; then cat '\(state.path)'; exit 0; fi
        printf '%s\\n' "$@" >> '\(log.path)'
        cp '\(after.path)' '\(state.path)'
        """
        try code.write(to:script,atomically:true,encoding:.utf8);try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:script.path)
        try write(configuration(["/":["Proxy":"http://127.0.0.1:3000"]]),to:state)
        XCTAssertNil(TailscaleHosting.configure(localPort:48291,funnel:false,executablePath:script.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath:log.path))
        try write([:],to:state);try write(configuration(["/":["Proxy":"http://127.0.0.1:48291/"]]),to:after)
        XCTAssertEqual(TailscaleHosting.configure(localPort:48291,funnel:false,executablePath:script.path),"https://desktop.example.ts.net:8443")
        let previous=try Data(contentsOf:log)
        try write(configuration(["/":["Proxy":"http://127.0.0.1:48291"],"/other":["Proxy":"http://127.0.0.1:3000"]]),to:state)
        XCTAssertFalse(TailscaleHosting.remove(localPort:48291,address:"https://desktop.example.ts.net:8443",funnel:false,executablePath:script.path))
        XCTAssertEqual(try Data(contentsOf:log),previous)
        XCTAssertFalse(String(decoding:previous,as:UTF8.self).contains("reset"))
    }
}
#endif
