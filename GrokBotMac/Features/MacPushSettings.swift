import SwiftUI

/// Settings → Phone notifications.
struct MacPushSettings: View {
    @AppStorage(MacPush.enabledKey) private var enabled = false
    @AppStorage(MacPush.serverKey) private var server = MacPush.defaultServer
    @AppStorage(MacPush.textKey) private var includeText = false
    @State private var topic = MacPush.topic()
    @State private var feedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Send a notification to my phone when a Bot finishes or needs me", isOn: $enabled).toggleStyle(.switch)
            Text("This uses the free ntfy app, so there is no account to make. Install ntfy on your iPhone, tap +, and subscribe to this topic. Notifications are sent only while OpenGrokBot is in the background.")
                .font(.system(size: 12)).lineSpacing(3).foregroundStyle(MacTheme.secondary)
            HStack {
                Text(topic).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                MacPillButton(title: "Copy topic") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(topic, forType: .string) }
            }
            TextField("ntfy server", text: $server).textFieldStyle(.roundedBorder).font(.system(size: 12))
            Toggle("Include the Bot’s reply text", isOn: $includeText).toggleStyle(.checkbox).font(.system(size: 12))
            Text("Off by default. The topic name is the only thing protecting a notification, so anyone who learns it could read the text. Keep it private, or use your own server.")
                .font(.system(size: 12)).lineSpacing(3).foregroundStyle(MacTheme.secondary)
            HStack {
                MacPillButton(title: "Send a test") {
                    Task {
                        guard MacPush.validatedServer(server) != nil else { feedback = "Use an https:// server address such as https://ntfy.sh."; return }
                        feedback = await MacPush.send(title: "OpenGrokBot", body: "Notifications are working.", force: true) ? "Sent. Check your phone." : "The server did not accept it."
                    }
                }
                if let feedback { Text(feedback).font(.system(size: 12)).foregroundStyle(MacTheme.secondary) }
            }
        }.padding(20)
    }
}
