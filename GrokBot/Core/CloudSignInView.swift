import SwiftUI

struct CloudSignInView: View {
    @ObservedObject var account: CloudAccount
    @State private var email = ""
    @State private var password = ""
    @State private var create = false
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            if account.signedIn {
                Label(account.email,systemImage:"person.crop.circle").font(.headline)
                Button("Sign out of this device",role:.destructive) { Task { await account.signOut() } }
            } else {
                Text(create ? "Create your account":"Sign in to OpenGrokBot").font(.title3.weight(.medium))
                Text("Use the same account on your computer and iPhone.").foregroundStyle(.secondary)
                TextField("Email",text:$email).textContentType(.emailAddress).autocorrectionDisabled()
                    .accessibilityIdentifier("cloud-email")
                SecureField("Password",text:$password).textContentType(create ? .newPassword:.password)
                    .accessibilityIdentifier("cloud-password")
                Button(account.busy ? "Please wait…":create ? "Create account":"Sign in") {
                    Task { await account.signIn(email:email,password:password,create:create); password = "" }
                }.disabled(account.busy || !email.contains("@") || password.isEmpty || (create && password.count < 8))
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("cloud-sign-in")
                Button(create ? "Already have an account? Sign in":"New here? Create an account") { create.toggle(); account.error = nil; account.notice = nil }.disabled(account.busy)
                if create { Text("Use at least 8 characters. Confirm the email Supabase sends before signing in.").font(.caption).foregroundStyle(.secondary) }
                ForEach(["google","github"],id:\.self) { provider in
                    if account.providers.contains(provider) {
                        Button("Continue with " + (provider == "google" ? "Google":"GitHub")) { Task { await account.oauth(provider) } }.disabled(account.busy)
                    }
                }
            }
            if let notice = account.notice { Text(notice).font(.callout).foregroundStyle(.secondary) }
            if let error = account.error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
        }.task { await account.loadProviders() }
    }
}
