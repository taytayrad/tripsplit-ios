import AuthenticationServices
import CryptoKit
import SwiftUI

struct SignInView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var colorScheme
    @State private var nonce = ""
    @State private var testName = ""

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            StampCluster(size: 72)
            VStack(spacing: Spacing.xs) {
                Text("TripSplit").font(.largeTitle.bold())
                Text("Who paid, and who owes who.").font(.subheadline).foregroundStyle(Color.tsSecondary)
            }
            Spacer()
            if let invite = app.invitePreview {
                Text("\(PersonName.shown(invite.inviterName)) invited you to “\(invite.tripName)”")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.tsSecondary)
                    .multilineTextAlignment(.center)
            }
            SignInWithAppleButton(.signIn) { request in
                nonce = Self.randomNonce()
                request.requestedScopes = [.fullName]
                request.nonce = Self.sha256(nonce)
            } onCompletion: { result in
                guard case .success(let auth) = result,
                      let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                      let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else { return }
                Task { await app.signInWithApple(idToken: token, nonce: nonce, fullName: credential.fullName,
                                                 authorizationCode: credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)  // HIG: black vanishes on a dark background
            .frame(height: 50)
            .clipShape(.rect(cornerRadius: Radius.lg))
            #if DEBUG
            HStack {
                TextField("Test person’s name", text: $testName).textFieldStyle(.roundedBorder)
                Button("Sign in (Debug)") { Task { await app.signInAsTestPerson(testName) } }
                    .disabled(testName.isEmpty)
            }
            .font(.footnote)
            #endif
        }
        .padding(Spacing.lg)
        .background(Color(.systemGroupedBackground))
    }

    static func randomNonce() -> String {
        (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct NotificationsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            StampView(spec: .init(shape: .postage, glyph: .sun, ink: .orange, rotation: 5, offsetX: 0, offsetY: 0)).frame(width: 96)
            Text("Stay in the loop").font(.title3.weight(.semibold))
            Text("We’ll tell you when friends add expenses, pay you, or join your trips.")
                .font(.subheadline).foregroundStyle(Color.tsSecondary).multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Spacer()
            Button("Allow notifications") { Task { await app.requestNotifications() } }.buttonStyle(PrimaryButtonStyle())
            Button("Not now") { app.skipNotifications() }.foregroundStyle(Color.accentColor)
        }
        .padding(Spacing.lg)
        .background(Color(.systemGroupedBackground))
    }
}

struct PayMethodsView: View {
    @Environment(AppModel.self) private var app
    @State private var zelle = false
    @State private var appleCash = false
    /// Set on the Venmo screen; nil means no Venmo.
    @State private var venmoUsername: String?

    var body: some View {
        NavigationStack {
        VStack(spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("How do you get paid?").font(.largeTitle.bold())
                Text("Pick what you use. Friends only see a pay button for an app you both have.")
                    .font(.subheadline).foregroundStyle(Color.tsSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .top], Spacing.lg)
            Form {
                // Figma Profile [F8]: Venmo is one row whose value is the username, like Profile.
                Section {
                    NavigationLink { VenmoView(username: venmoUsername) { venmoUsername = $0 } } label: {
                        LabeledContent("Venmo", value: venmoUsername.map { "@\($0)" } ?? "Add")
                    }
                    CheckRow(title: "Zelle", isOn: $zelle)
                    CheckRow(title: "Apple Cash", isOn: $appleCash)
                }
            }
            .scrollContentBackground(.hidden)
            VStack(spacing: Spacing.sm) {
                Button("Continue") {
                    Task { await app.savePayMethods(venmo: venmoUsername, zelle: zelle, appleCash: appleCash) }
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Skip for now") { Task { await app.finishOnboarding() } }.foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, Spacing.lg)
        }
        .padding(.bottom, Spacing.lg)
        .background(Color(.systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
        }
    }
}
