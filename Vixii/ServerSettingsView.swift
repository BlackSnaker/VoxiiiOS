import SwiftUI

struct ServerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var appearance: VoxiiAppearance
    @State private var draftURL: String
    @State private var isChecking = false
    @State private var connectionMessage: String?
    @State private var connectionIsError = false
    let onApply: (String) -> Void

    init(initialURL: String, onApply: @escaping (String) -> Void) {
        _draftURL = State(initialValue: initialURL)
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VoxiiBackground()

                VStack(spacing: 12) {
                    HStack {
                        Button(appearance.t("common.cancel")) {
                            dismiss()
                        }
                        .buttonStyle(VoxiiGradientButtonStyle(isCompact: true, variant: .neutral))

                        Spacer()

                        Text(appearance.t("server.title"))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(VoxiiTheme.text)

                        Spacer()

                        Button(appearance.t("common.apply")) {
                            Task { await applyServerURL() }
                        }
                        .buttonStyle(VoxiiGradientButtonStyle(isCompact: true))
                        .disabled(isChecking || draftURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .voxiiCard(cornerRadius: 18, padding: 12)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(appearance.t("server.urlLabel"))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(VoxiiTheme.mutedSecondary)

                        TextField("https://voxii.lenuma.ru", text: $draftURL)
                            .keyboardType(.URL)
                            .voxiiInput()

                        HStack(spacing: 10) {
                            Button {
                                Task { await testConnection() }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "network")
                                    Text(appearance.t("server.testConnection"))
                                }
                            }
                            .buttonStyle(VoxiiGradientButtonStyle(isCompact: true, variant: .neutral))
                            .disabled(isChecking || draftURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            if isChecking {
                                ProgressView()
                                    .tint(VoxiiTheme.accent)
                            }
                        }

                        if let connectionMessage {
                            HStack(spacing: 6) {
                                Image(systemName: connectionIsError ? "xmark.octagon.fill" : "checkmark.seal.fill")
                                    .foregroundStyle(connectionIsError ? VoxiiTheme.danger : VoxiiTheme.online)
                                Text(connectionMessage)
                                    .foregroundStyle(connectionIsError ? VoxiiTheme.danger : VoxiiTheme.online)
                            }
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .transition(.opacity)
                        }
                    }
                    .voxiiCard(cornerRadius: 16, padding: 14)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(appearance.t("server.quickPresets"))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(VoxiiTheme.mutedSecondary)

                        Button(appearance.t("server.production")) {
                            draftURL = "https://voxii.lenuma.ru"
                            resetStatus()
                        }
                        .buttonStyle(VoxiiGradientButtonStyle(variant: .neutral))

                        Button(appearance.t("server.localhost")) {
                            draftURL = "http://127.0.0.1:3000"
                            resetStatus()
                        }
                        .buttonStyle(VoxiiGradientButtonStyle(variant: .neutral))

                        Button(appearance.t("server.lanExample")) {
                            draftURL = "http://192.168.1.10:3000"
                            resetStatus()
                        }
                        .buttonStyle(VoxiiGradientButtonStyle(variant: .neutral))
                    }
                    .voxiiCard(cornerRadius: 16, padding: 14)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(appearance.t("server.notes"))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(VoxiiTheme.mutedSecondary)

                        Text(appearance.t("server.note1"))
                            .foregroundStyle(VoxiiTheme.muted)
                        Text(appearance.t("server.note2"))
                            .foregroundStyle(VoxiiTheme.muted)
                        Text(appearance.t("server.note3"))
                            .foregroundStyle(VoxiiTheme.muted)
                        Text(appearance.t("server.note4"))
                            .foregroundStyle(VoxiiTheme.muted)
                        Text(appearance.t("server.note5"))
                            .foregroundStyle(VoxiiTheme.muted)
                        Text(appearance.t("server.note6"))
                            .foregroundStyle(VoxiiTheme.muted)
                    }
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .voxiiCard(cornerRadius: 16, padding: 14)

                    Spacer(minLength: 0)
                }
            }
            .padding(12)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func applyServerURL() async {
        isChecking = true
        defer { isChecking = false }
        do {
            let normalized = try await session.testServerConnection(draftURL)
            draftURL = normalized
            connectionIsError = false
            connectionMessage = appearance.t("server.connected")
            onApply(normalized)
            dismiss()
        } catch {
            connectionIsError = true
            connectionMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func testConnection() async {
        isChecking = true
        defer { isChecking = false }
        do {
            let normalized = try await session.testServerConnection(draftURL)
            draftURL = normalized
            connectionIsError = false
            connectionMessage = appearance.t("server.reachable")
        } catch {
            connectionIsError = true
            connectionMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func resetStatus() {
        connectionMessage = nil
        connectionIsError = false
    }
}
