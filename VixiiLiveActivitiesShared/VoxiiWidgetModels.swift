import Foundation

enum VoxiiWidgetShared {
    static let appGroupID = "group.Illumionix.Vixii.shared"
    static let inboxSnapshotKey = "voxii.widget.inboxSnapshot"
}

struct VoxiiInboxWidgetContact: Codable, Hashable, Identifiable {
    let id: Int
    let username: String
    let avatarText: String
    let email: String?
    let isOnline: Bool
    let isFriend: Bool
    let unreadCount: Int
}

struct VoxiiInboxWidgetSnapshot: Codable, Hashable {
    let generatedAt: Date
    let currentUsername: String
    let totalUnread: Int
    let onlineFriends: Int
    let totalContacts: Int
    let contacts: [VoxiiInboxWidgetContact]

    var topContact: VoxiiInboxWidgetContact? {
        contacts.first
    }

    static func empty(currentUsername: String = "") -> VoxiiInboxWidgetSnapshot {
        VoxiiInboxWidgetSnapshot(
            generatedAt: Date(),
            currentUsername: currentUsername,
            totalUnread: 0,
            onlineFriends: 0,
            totalContacts: 0,
            contacts: []
        )
    }
}

enum VoxiiWidgetStore {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: VoxiiWidgetShared.appGroupID)
    }

    static func loadInboxSnapshot() -> VoxiiInboxWidgetSnapshot? {
        guard let data = sharedDefaults()?.data(forKey: VoxiiWidgetShared.inboxSnapshotKey) else {
            return nil
        }
        return try? decoder.decode(VoxiiInboxWidgetSnapshot.self, from: data)
    }

    static func saveInboxSnapshot(_ snapshot: VoxiiInboxWidgetSnapshot) {
        guard let defaults = sharedDefaults(),
              let data = try? encoder.encode(snapshot) else {
            return
        }
        defaults.set(data, forKey: VoxiiWidgetShared.inboxSnapshotKey)
    }

    static func clearInboxSnapshot() {
        sharedDefaults()?.removeObject(forKey: VoxiiWidgetShared.inboxSnapshotKey)
    }
}
