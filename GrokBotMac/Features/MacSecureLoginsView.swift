import SwiftUI

/// Settings → Secure Logins. Saved logins are filled in by the app after you approve; the Bot never sees the password.
struct MacSecureLoginsView: View {
    private let store = SecureLoginStore()
    @State private var logins: [SecureLogin] = []
    @State private var label = ""
    @State private var website = ""
    @State private var username = ""
    @State private var password = ""
    @State private var useOnePassword = false
    @State private var onePasswordItem = ""
    @State private var feedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Let a Bot sign in without seeing your password").font(.system(size: 18, weight: .medium))
                Text("Save a login here, then ask a Bot to sign in. Each time, a dialog shows the site and account, and you approve with Touch ID or your Mac password. OpenGrokBot types the password into the page itself: the Bot and its AI provider never see it, and it never appears in the chat.")
                    .font(.system(size: 14)).lineSpacing(4).foregroundStyle(MacTheme.secondary)
                Text("A login only works on the website you save it for, and its subdomains. Verification codes and passkeys are not handled: you finish those yourself in the Bot’s browser. Passwords are stored in this Mac’s Keychain.")
                    .font(.system(size: 13)).lineSpacing(4).foregroundStyle(MacTheme.secondary)
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 12) {
                Text("Add a login").font(.system(size: 16, weight: .medium))
                TextField("Name, for example ESPN", text: $label).textFieldStyle(.roundedBorder)
                TextField("Website, for example https://www.espn.com/login", text: $website).textFieldStyle(.roundedBorder).autocorrectionDisabled()
                Toggle("Use an item from 1Password instead of saving a password here", isOn: $useOnePassword).toggleStyle(.checkbox).font(.system(size: 13))
                if useOnePassword {
                    TextField("Exact 1Password item name", text: $onePasswordItem).textFieldStyle(.roundedBorder).autocorrectionDisabled()
                    Text(OnePassword.executable == nil ? "1Password’s command-line tool (op) was not found. Install it with brew install 1password-cli, then turn on its desktop app integration." : "1Password will ask for Touch ID each time. Nothing is stored here but the item name.")
                        .font(.system(size: 12)).foregroundStyle(MacTheme.secondary)
                } else {
                    TextField("Username or email", text: $username).textFieldStyle(.roundedBorder).autocorrectionDisabled()
                    SecureField("Password", text: $password).textFieldStyle(.roundedBorder).accessibilityIdentifier("secure-login-password")
                }
                HStack {
                    MacPillButton(title: "Save to Keychain", prominent: true) { save() }
                        .disabled(label.isEmpty || website.isEmpty || (useOnePassword ? onePasswordItem.isEmpty : (username.isEmpty || password.isEmpty)))
                    if let feedback { Text(feedback).font(.system(size: 13)).foregroundStyle(MacTheme.secondary) }
                }
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 0) {
                Text("Saved logins").font(.system(size: 14)).foregroundStyle(MacTheme.secondary).padding(.leading, 16).padding(.bottom, 10)
                if logins.isEmpty {
                    Text("No logins saved yet.").font(.system(size: 14)).foregroundStyle(MacTheme.secondary).padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading).background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 18))
                } else {
                    VStack(spacing: 0) {
                        ForEach(logins) { login in
                            HStack {
                                Image(systemName: "key.fill").frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(login.label).font(.system(size: 15, weight: .medium))
                                    Text(login.onePassword != nil ? "1Password · \(login.host)" : "\(login.username) · \(login.host)").font(.system(size: 12)).foregroundStyle(MacTheme.secondary)
                                }
                                Spacer()
                                MacPillButton(title: "Remove") { remove(login) }
                            }.padding(16)
                            if login.id != logins.last?.id { Divider() }
                        }
                    }.background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }.onAppear { logins = store.list() }
    }

    private func save() {
        do {
            if useOnePassword { try store.addOnePassword(label: label, url: website, item: onePasswordItem) }
            else { try store.add(label: label, url: website, username: username, password: password) }
            label = ""; website = ""; username = ""; password = ""; onePasswordItem = ""
            feedback = "Saved in this Mac’s Keychain."
        } catch { feedback = (error as? LocalizedError)?.errorDescription ?? "The login could not be saved." }
        logins = store.list()
    }

    private func remove(_ login: SecureLogin) {
        do { try store.remove(login.id); feedback = "Removed \(login.label)." } catch { feedback = "The Keychain could not remove this login. Unlock your Mac and try again." }
        logins = store.list()
    }
}
