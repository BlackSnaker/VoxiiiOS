import SwiftUI

struct ServerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
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
                        Button("Cancel") {
                            dismiss()
                        }
                        .buttonStyle(VoxiiGradientButtonStyle(isCompact: true, variant: .neutral))

                        Spacer()

                        Text("Voxii Server")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(VoxiiTheme.text)

                        Spacer()

                        Button("Apply") {
                            Task { await applyServerURL() }
                        }
                        .buttonStyle(VoxiiGradientButtonStyle(isCompact: true))
                        .disabled(isChecking || draftURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .voxiiCard(cornerRadius: 18, padding: 12)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("SERVER URL")
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
                                    Text("Test Connection")
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
                        Text("QUICK PRESETS")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(VoxiiTheme.mutedSecondary)

                        Button("Production Server") {
                            draftURL = "https://voxii.lenuma.ru"
                            resetStatus()
                        }
                        .buttonStyle(VoxiiGradientButtonStyle(variant: .neutral))

                        Button("Localhost (Simulator)") {
                            draftURL = "http://127.0.0.1:3000"
                            resetStatus()
                        }
                        .buttonStyle(VoxiiGradientButtonStyle(variant: .neutral))

                        Button("Example LAN Address") {
                            draftURL = "http://192.168.1.10:3000"
                            resetStatus()
                        }
                        .buttonStyle(VoxiiGradientButtonStyle(variant: .neutral))
                    }
                    .voxiiCard(cornerRadius: 16, padding: 14)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("NOTES")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(VoxiiTheme.mutedSecondary)

                        Text("Use 127.0.0.1 in iOS Simulator when Voxii backend runs on the same Mac.")
                            .foregroundStyle(VoxiiTheme.muted)
                        Text("Default production server: https://voxii.lenuma.ru")
                            .foregroundStyle(VoxiiTheme.muted)
                        Text("Use your production domain with a valid certificate for iPhone and App Store builds.")
                            .foregroundStyle(VoxiiTheme.muted)
                        Text("For physical iPhone, use your Mac LAN IP and ensure both devices are in one network.")
                            .foregroundStyle(VoxiiTheme.muted)
                        Text("If scheme is omitted, Voxii tries HTTPS first and then HTTP.")
                            .foregroundStyle(VoxiiTheme.muted)
                        Text("For production domains, HTTPS is recommended.")
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
            connectionMessage = "Connected successfully."
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
            connectionMessage = "Server is reachable."
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
