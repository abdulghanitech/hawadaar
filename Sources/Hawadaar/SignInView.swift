import HawadaarCore
import SwiftUI

struct SignInView: View {
    @EnvironmentObject var store: ACStore
    let error: String?
    @State private var username = ""
    @State private var password = ""
    @State private var busy = false

    private var identifier: MirAIeAPI.LoginIdentifier? { MirAIeAPI.loginIdentifier(for: username) }
    private var canSubmit: Bool { identifier != nil && !password.isEmpty && !busy }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                BrandHeader(subtitle: "Sign in with your MirAIe account")
                Text("Use the same login as the MirAIe app. Your password stays in your Keychain and is only sent to MirAIe.")
                    .font(.caption).foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Mobile number or email").font(.caption).bold()
                TextField("98765 43210", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.username)
                usernameHint
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Password").font(.caption).bold()
                SecureField("MirAIe password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                    .onSubmit(submit)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Quit") { NSApp.terminate(nil) }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("Sign In", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
        }
        .padding(16)
    }

    /// Explains the expected format, then confirms exactly what will be sent as the user types.
    @ViewBuilder private var usernameHint: some View {
        Group {
            if let identifier {
                switch identifier {
                case .mobile(let number):
                    Label { Text("Signing in as ") + Text(Self.formatted(number)).bold() } icon: { Image(systemName: "phone.fill") }
                        .foregroundStyle(.green)
                case .email(let address):
                    Label { Text("Signing in as ") + Text(address).bold() } icon: { Image(systemName: "envelope.fill") }
                        .foregroundStyle(.green)
                }
            } else if let problem = Self.problem(with: username) {
                Label(problem, systemImage: "exclamationmark.circle").foregroundStyle(.orange)
            } else {
                Text("Indian numbers don't need +91. Outside India, start with your country code, e.g. +44.")
                    .foregroundStyle(Palette.secondary)
            }
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeOut(duration: 0.15), value: identifier)
    }

    /// Why the input isn't a valid username yet, or nil when it's empty.
    private static func problem(with input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("@") { return "Check the email address." }
        let digits = trimmed.filter(\.isNumber).count
        if trimmed.contains(where: \.isLetter) { return "Enter a mobile number or an email address." }
        if trimmed.hasPrefix("+") { return "Include the full number after the country code." }
        if digits < 10 { return "Mobile numbers need 10 digits (\(digits) so far)." }
        return "Too many digits. Outside India, start with + and your country code."
    }

    /// "+919876543210" → "+91 98765 43210"; other countries are shown as entered.
    private static func formatted(_ number: String) -> String {
        guard number.hasPrefix("+91"), number.count == 13 else { return number }
        let digits = number.dropFirst(3)
        return "+91 \(digits.prefix(5)) \(digits.suffix(5))"
    }

    private func submit() {
        guard canSubmit else { return }
        busy = true
        Task {
            await store.signIn(username: username, password: password)
            busy = false
        }
    }
}
