import SwiftUI

struct ContentView: View {
    @StateObject private var session = SessionStore()
    @StateObject private var appearance = VoxiiAppearance.shared
    @StateObject private var router = VoxiiAppRouter()

    var body: some View {
        ZStack {
            if session.isAuthenticated {
                MessengerHomeView()
                    .environmentObject(session)
                    .environmentObject(appearance)
                    .environmentObject(router)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.985)),
                            removal: .opacity
                        )
                    )
            } else {
                AuthView()
                    .environmentObject(session)
                    .environmentObject(appearance)
                    .environmentObject(router)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.985)),
                            removal: .opacity
                        )
                    )
            }
        }
        .tint(VoxiiTheme.accent)
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: session.isAuthenticated)
        .onAppear {
            VoxiiSystemAppearance.apply()
        }
        .onChange(of: appearance.refreshID) { _, _ in
            VoxiiSystemAppearance.apply()
        }
        .onOpenURL { url in
            router.handle(url)
        }
        .id(appearance.refreshID)
    }
}
