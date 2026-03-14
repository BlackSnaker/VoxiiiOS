import Foundation
import WidgetKit

@MainActor
enum VoxiiWidgetSnapshotManager {
    static func saveSignedInUser(_ user: APIUser) {
        let existing = VoxiiWidgetStore.loadInboxSnapshot()
        let snapshot = VoxiiInboxWidgetSnapshot(
            generatedAt: existing?.generatedAt ?? Date(),
            currentUsername: user.username,
            totalUnread: existing?.totalUnread ?? 0,
            onlineFriends: existing?.onlineFriends ?? 0,
            totalContacts: existing?.totalContacts ?? 0,
            contacts: existing?.contacts ?? []
        )
        VoxiiWidgetStore.saveInboxSnapshot(snapshot)
        reloadAllTimelines()
    }

    static func publishInbox(
        users: [APIUser],
        friendIDs: Set<Int>,
        unreadByUser: [Int: Int],
        currentUser: APIUser?
    ) {
        let contacts = users
            .map { user in
                VoxiiInboxWidgetContact(
                    id: user.id,
                    username: user.username,
                    avatarText: (user.avatar?.isEmpty == false ? user.avatar! : user.username),
                    email: user.email,
                    isOnline: user.status?.lowercased() == "online",
                    isFriend: friendIDs.contains(user.id),
                    unreadCount: unreadByUser[user.id] ?? 0
                )
            }
            .sorted(by: contactComparator)

        let snapshot = VoxiiInboxWidgetSnapshot(
            generatedAt: Date(),
            currentUsername: currentUser?.username ?? "",
            totalUnread: unreadByUser.values.reduce(0, +),
            onlineFriends: contacts.filter { $0.isFriend && $0.isOnline }.count,
            totalContacts: contacts.count,
            contacts: Array(contacts.prefix(4))
        )
        VoxiiWidgetStore.saveInboxSnapshot(snapshot)
        reloadAllTimelines()
    }

    static func clearAll() {
        VoxiiWidgetStore.clearInboxSnapshot()
        reloadAllTimelines()
    }

    private static func reloadAllTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static let contactComparator: (VoxiiInboxWidgetContact, VoxiiInboxWidgetContact) -> Bool = { lhs, rhs in
        if lhs.unreadCount != rhs.unreadCount {
            return lhs.unreadCount > rhs.unreadCount
        }
        if lhs.isFriend != rhs.isFriend {
            return lhs.isFriend && !rhs.isFriend
        }
        if lhs.isOnline != rhs.isOnline {
            return lhs.isOnline && !rhs.isOnline
        }
        return lhs.username.localizedCaseInsensitiveCompare(rhs.username) == .orderedAscending
    }
}
