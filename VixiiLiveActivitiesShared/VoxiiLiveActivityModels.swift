import ActivityKit
import Foundation

struct VoxiiMessageActivityAttributes: ActivityAttributes, Identifiable {
    public struct ContentState: Codable, Hashable {
        var senderName: String
        var previewText: String
        var statusText: String
        var unreadCount: Int
        var receivedAt: Date
    }

    let conversationID: String
    let avatarText: String
    let deepLink: String

    var id: String { conversationID }
}

struct VoxiiCallActivityAttributes: ActivityAttributes, Identifiable {
    enum CallType: String, Codable, Hashable {
        case audio
        case video
    }

    enum Phase: String, Codable, Hashable {
        case incoming
        case calling
        case connecting
        case connected
        case ended
        case missed
    }

    public struct ContentState: Codable, Hashable {
        var phase: Phase
        var statusText: String
        var connectedSince: Date?
        var updatedAt: Date
    }

    let eventID: String
    let callerName: String
    let avatarText: String
    let callType: CallType
    let deepLink: String

    var id: String { eventID }
}
