#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import GrokBotMac

final class MacVisualTests: XCTestCase {
    @MainActor
    func testDesktopReferenceLayoutsRender() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = AppModel(store: WorkspaceStore(url: directory.appendingPathComponent("preview.json")))
        app.enterPreview()
        let desktop = MacAppModel()
        desktop.selectFirst(in: app)
        let root = MacWorkspaceView().environmentObject(app).environmentObject(desktop).preferredColorScheme(.dark)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1370, height: 940), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        for (name, panel) in [("macos-workspace", Optional<MacPanel>.none), ("macos-connect-apps", .apps), ("macos-settings", .settings)] {
            desktop.panel = panel
            try await Task.sleep(for: .milliseconds(200))
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let representation = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: representation)
            XCTAssertGreaterThan(representation.pixelsWide, 1000)
            let image = NSImage(size: host.bounds.size)
            image.addRepresentation(representation)
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
#endif
