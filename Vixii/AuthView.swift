import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var appearance: VoxiiAppearance
    @State private var mode: Mode = .login
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isSettingsPresented = false
    @State private var serverURLDraft = ""

    private enum Mode: CaseIterable, Identifiable {
        case login
        case register

        var id: String {
            switch self {
            case .login:
                return "login"
            case .register:
                return "register"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VoxiiBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        VStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(VoxiiTheme.accentGradient)
                                    .frame(width: 62, height: 62)
                                    .overlay(
                                        Image(systemName: "bolt.horizontal.circle.fill")
                                            .font(.system(size: 30, weight: .bold))
                                            .foregroundStyle(.white)
                                    )
                            }
                            .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 7)

                            Text(mode == .login ? appearance.t("auth.welcomeBack") : appearance.t("auth.createAccount"))
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(VoxiiTheme.text)

                            Text(mode == .login ? appearance.t("auth.loginSubtitle") : appearance.t("auth.registerSubtitle"))
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(VoxiiTheme.muted)
                        }
                        .padding(.bottom, 6)

                        HStack(spacing: 8) {
                            ForEach(Mode.allCases) { item in
                                Button {
                                    withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                                        mode = item
                                    }
                                } label: {
                                    Text(item == .login ? appearance.t("auth.mode.login") : appearance.t("auth.mode.register"))
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(mode == item ? AnyShapeStyle(VoxiiTheme.accentGradient) : AnyShapeStyle(Color.clear))
                                        )
                                }
                            }
                        }
                        .padding(4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .background(
                            Capsule(style: .continuous)
                                .fill(VoxiiTheme.glass.opacity(0.84))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(VoxiiTheme.stroke, lineWidth: 1)
                        )

                        if mode == .register {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(appearance.t("auth.usernameLabel"))
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(VoxiiTheme.mutedSecondary)

                                TextField(appearance.t("auth.usernamePlaceholder"), text: $username)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .voxiiInput()
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(appearance.t("auth.emailLabel"))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(VoxiiTheme.mutedSecondary)

                            TextField("name@example.com", text: $email)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .voxiiInput()
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(appearance.t("auth.passwordLabel"))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(VoxiiTheme.mutedSecondary)

                            SecureField(appearance.t("auth.passwordPlaceholder"), text: $password)
                                .voxiiInput()
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            Group {
                                if session.isBusy {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text(mode == .login ? appearance.t("auth.submit.login") : appearance.t("auth.submit.register"))
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(VoxiiGradientButtonStyle())
                        .opacity(canSubmit ? 1 : 0.58)
                        .disabled(session.isBusy || !canSubmit)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(appearance.t("auth.serverLabel"))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(VoxiiTheme.mutedSecondary)

                            HStack(spacing: 10) {
                                Image(systemName: "network")
                                    .foregroundStyle(VoxiiTheme.accentLight)

                                Text(session.serverURL)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(VoxiiTheme.text)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)

                                Spacer()

                                Button(appearance.t("common.change")) {
                                    serverURLDraft = session.serverURL
                                    isSettingsPresented = true
                                }
                                .buttonStyle(VoxiiGradientButtonStyle(isCompact: true, variant: .neutral))
                            }
                            .voxiiCard(cornerRadius: 12, padding: 10)
                        }

                        if let error = session.errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(VoxiiTheme.danger)

                                Text(error)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(VoxiiTheme.text)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.red.opacity(0.16))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.red.opacity(0.4), lineWidth: 1)
                            )
                        }
                    }
                    .voxiiCard(cornerRadius: 22, padding: 22)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isSettingsPresented) {
                ServerSettingsView(initialURL: serverURLDraft) { newValue in
                    session.updateServerURL(newValue)
                }
            }
        }
    }

    private var canSubmit: Bool {
        guard isValidEmail(email) else {
            return false
        }

        guard password.count >= 6 else {
            return false
        }

        if mode == .register {
            return username.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
        }

        return true
    }

    private func isValidEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    private func submit() async {
        if mode == .login {
            _ = await session.login(email: email, password: password)
        } else {
            _ = await session.register(username: username, email: email, password: password)
        }
    }
}
