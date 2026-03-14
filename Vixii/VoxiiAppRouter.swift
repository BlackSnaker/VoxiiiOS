import Foundation
import Combine

@MainActor
final class VoxiiAppRouter: ObservableObject {
    enum Route: Equatable {
        case messages
        case chat(Int)
        case friends
        case news
        case notifications
        case settings
        case call(String)
    }

    @Published private(set) var route: Route?

    func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "voxii" else {
            return
        }

        let host = url.host?.lowercased() ?? ""
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "messages":
            if pathComponents.count >= 2,
               pathComponents[0] == "contact",
               let userID = Int(pathComponents[1]) {
                route = .chat(userID)
            } else {
                route = .messages
            }
        case "friends":
            route = .friends
        case "news":
            route = .news
        case "notifications":
            route = .notifications
        case "settings":
            route = .settings
        case "call":
            route = .call(pathComponents.first ?? "")
        default:
            route = .messages
        }
    }

    func consumeRoute() -> Route? {
        let current = route
        route = nil
        return current
    }
}
