import SwiftUI
import WidgetKit

struct VoxiiInboxWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: VoxiiInboxWidgetSnapshot?
    let isPreview: Bool
}

struct VoxiiInboxWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> VoxiiInboxWidgetEntry {
        VoxiiInboxWidgetEntry(date: Date(), snapshot: previewSnapshot, isPreview: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (VoxiiInboxWidgetEntry) -> Void) {
        let snapshot = context.isPreview ? previewSnapshot : VoxiiWidgetStore.loadInboxSnapshot()
        completion(
            VoxiiInboxWidgetEntry(
                date: Date(),
                snapshot: snapshot ?? previewSnapshot,
                isPreview: context.isPreview
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VoxiiInboxWidgetEntry>) -> Void) {
        let entry = VoxiiInboxWidgetEntry(
            date: Date(),
            snapshot: VoxiiWidgetStore.loadInboxSnapshot(),
            isPreview: false
        )
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private var previewSnapshot: VoxiiInboxWidgetSnapshot {
        VoxiiInboxWidgetSnapshot(
            generatedAt: Date(),
            currentUsername: "Oleg",
            totalUnread: 6,
            onlineFriends: 4,
            totalContacts: 12,
            contacts: [
                VoxiiInboxWidgetContact(id: 1, username: "Aria", avatarText: "A", email: "aria@voxii.app", isOnline: true, isFriend: true, unreadCount: 3),
                VoxiiInboxWidgetContact(id: 2, username: "Noah", avatarText: "N", email: "noah@voxii.app", isOnline: true, isFriend: true, unreadCount: 2),
                VoxiiInboxWidgetContact(id: 3, username: "Mia", avatarText: "M", email: "mia@voxii.app", isOnline: false, isFriend: false, unreadCount: 1),
                VoxiiInboxWidgetContact(id: 4, username: "Leo", avatarText: "L", email: "leo@voxii.app", isOnline: true, isFriend: false, unreadCount: 0)
            ]
        )
    }
}

struct VoxiiInboxSummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VoxiiInboxSummaryWidget", provider: VoxiiInboxWidgetProvider()) { entry in
            VoxiiInboxSummaryWidgetView(entry: entry)
        }
        .configurationDisplayName(widgetText(ru: "Voxii: сводка", en: "Voxii Summary"))
        .description(widgetText(ru: "Быстрый статус входящих и главный чат на рабочем столе.", en: "Quick inbox status and your priority chat on the Home Screen."))
        .supportedFamilies([.systemSmall])
    }
}

struct VoxiiInboxContactsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VoxiiInboxContactsWidget", provider: VoxiiInboxWidgetProvider()) { entry in
            VoxiiInboxContactsWidgetView(entry: entry)
        }
        .configurationDisplayName(widgetText(ru: "Voxii: чаты", en: "Voxii Chats"))
        .description(widgetText(ru: "Три важных диалога и быстрый переход в нужный чат.", en: "Three key chats with direct access to the right conversation."))
        .supportedFamilies([.systemMedium])
    }
}

struct VoxiiInboxDashboardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VoxiiInboxDashboardWidget", provider: VoxiiInboxWidgetProvider()) { entry in
            VoxiiInboxDashboardWidgetView(entry: entry)
        }
        .configurationDisplayName(widgetText(ru: "Voxii: дашборд", en: "Voxii Dashboard"))
        .description(widgetText(ru: "Большая карточка с приоритетным чатом, списком диалогов и быстрыми разделами.", en: "A large dashboard with a priority chat, conversation list, and quick sections."))
        .supportedFamilies([.systemLarge])
    }
}

private struct VoxiiInboxSummaryWidgetView: View {
    let entry: VoxiiInboxWidgetEntry

    var body: some View {
        let snapshot = entry.snapshot
        let priority = snapshot?.contacts.first

        ZStack {
            widgetBackground

            VStack(alignment: .leading, spacing: 12) {
                widgetHeader(
                    title: "Voxii",
                    subtitle: widgetText(ru: "Входящие", en: "Inbox"),
                    date: snapshot?.generatedAt
                )

                if let snapshot {
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text("\(snapshot.totalUnread)")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundStyle(.white)

                        Text(unreadCaption(for: snapshot.totalUnread))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.bottom, 4)
                    }

                    if let priority {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                widgetAvatar(priority, size: 36)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(priority.username)
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)

                                    Text(prioritySubtitle(priority))
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.66))
                                        .lineLimit(2)
                                }

                                Spacer(minLength: 0)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(widgetPanel(prominence: .primary))
                    } else {
                        widgetEmptyState(
                            title: widgetText(ru: "Тишина в чатах", en: "Quiet inbox"),
                            subtitle: widgetText(ru: "Откройте Voxii и обновите сводку диалогов.", en: "Open Voxii and refresh your conversation summary.")
                        )
                    }

                    HStack(spacing: 8) {
                        widgetMetric(icon: "person.2.fill", value: "\(snapshot.onlineFriends)", label: widgetText(ru: "онлайн", en: "online"))
                        widgetMetric(icon: "bubble.left.and.bubble.right.fill", value: "\(snapshot.totalContacts)", label: widgetText(ru: "чатов", en: "chats"))
                    }
                } else {
                    widgetEmptyState(
                        title: widgetText(ru: "Нет данных", en: "No data"),
                        subtitle: widgetText(ru: "Откройте приложение, чтобы наполнить виджет актуальными диалогами.", en: "Open the app to fill the widget with your current chats.")
                    )
                }
            }
            .padding(16)
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: priority.map { "voxii://messages/contact/\($0.id)" } ?? "voxii://messages"))
    }

    private func prioritySubtitle(_ contact: VoxiiInboxWidgetContact) -> String {
        if contact.unreadCount > 0 {
            return widgetText(ru: "\(contact.unreadCount) непрочитанных", en: "\(contact.unreadCount) unread")
        }
        if contact.isOnline {
            return widgetText(ru: "Сейчас в сети", en: "Online now")
        }
        return widgetText(ru: "Открыть переписку", en: "Open conversation")
    }
}

private struct VoxiiInboxContactsWidgetView: View {
    let entry: VoxiiInboxWidgetEntry

    var body: some View {
        let snapshot = entry.snapshot

        ZStack {
            widgetBackground

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    widgetHeader(
                        title: widgetText(ru: "Быстрые чаты", en: "Quick Chats"),
                        subtitle: mediumSubtitle(snapshot),
                        date: snapshot?.generatedAt,
                        compact: true
                    )

                    Spacer(minLength: 0)

                    Link(destination: URL(string: "voxii://messages")!) {
                        widgetActionChip(icon: "arrow.up.left.and.arrow.down.right", title: widgetText(ru: "Открыть", en: "Open"))
                    }
                }

                if let snapshot, !snapshot.contacts.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(snapshot.contacts.prefix(3)) { contact in
                            Link(destination: URL(string: "voxii://messages/contact/\(contact.id)")!) {
                                widgetChatRow(contact, style: .medium)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    widgetEmptyState(
                        title: widgetText(ru: "Нет чатов", en: "No chats yet"),
                        subtitle: widgetText(ru: "Откройте Voxii, чтобы синхронизировать список диалогов для рабочего стола.", en: "Open Voxii to sync your chats for the Home Screen.")
                    )
                }
            }
            .padding(16)
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private func mediumSubtitle(_ snapshot: VoxiiInboxWidgetSnapshot?) -> String {
        guard let snapshot else {
            return widgetText(ru: "Синхронизация ожидается", en: "Waiting for sync")
        }
        if snapshot.totalUnread > 0 {
            return widgetText(ru: "\(snapshot.totalUnread) непрочитанных • \(snapshot.onlineFriends) онлайн", en: "\(snapshot.totalUnread) unread • \(snapshot.onlineFriends) online")
        }
        return widgetText(ru: "Все чаты под контролем", en: "All chats are under control")
    }
}

private struct VoxiiInboxDashboardWidgetView: View {
    let entry: VoxiiInboxWidgetEntry

    var body: some View {
        let snapshot = entry.snapshot
        let priority = snapshot?.contacts.first
        let additionalContacts = Array(snapshot?.contacts.dropFirst().prefix(4) ?? [])

        ZStack {
            widgetBackground

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    widgetHeader(
                        title: widgetText(ru: "Voxii Dashboard", en: "Voxii Dashboard"),
                        subtitle: dashboardSubtitle(snapshot),
                        date: snapshot?.generatedAt,
                        compact: true
                    )

                    Spacer(minLength: 0)

                    HStack(spacing: 8) {
                        widgetStatusBadge(icon: "bubble.left.and.bubble.right.fill", text: "\(snapshot?.totalUnread ?? 0)")
                        widgetStatusBadge(icon: "person.2.fill", text: "\(snapshot?.onlineFriends ?? 0)")
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(widgetText(ru: "Приоритетный чат", en: "Priority Chat"))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))

                        if let priority {
                            Link(destination: URL(string: "voxii://messages/contact/\(priority.id)")!) {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 10) {
                                        widgetAvatar(priority, size: 44)

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(priority.username)
                                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)

                                            Text(priorityHeadline(priority))
                                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                                .foregroundStyle(.white.opacity(0.7))
                                                .lineLimit(2)
                                        }

                                        Spacer(minLength: 0)
                                    }

                                    HStack(spacing: 8) {
                                        widgetInlineTag(
                                            icon: priority.isOnline ? "dot.radiowaves.left.and.right" : "moon.stars.fill",
                                            title: priority.isOnline ? widgetText(ru: "в сети", en: "online") : widgetText(ru: "не в сети", en: "offline")
                                        )
                                        if priority.isFriend {
                                            widgetInlineTag(icon: "star.fill", title: widgetText(ru: "друг", en: "friend"))
                                        }
                                    }
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(widgetPanel(prominence: .primary))
                            }
                            .buttonStyle(.plain)
                        } else {
                            widgetEmptyState(
                                title: widgetText(ru: "Нет данных для чатов", en: "No chat data yet"),
                                subtitle: widgetText(ru: "Откройте Voxii, чтобы виджет получил актуальную сводку.", en: "Open Voxii so the widget can receive a fresh summary.")
                            )
                        }

                        HStack(spacing: 8) {
                            Link(destination: URL(string: "voxii://messages")!) {
                                widgetShortcut(icon: "message.fill", title: widgetText(ru: "Сообщения", en: "Messages"))
                            }
                            Link(destination: URL(string: "voxii://friends")!) {
                                widgetShortcut(icon: "person.2.fill", title: widgetText(ru: "Друзья", en: "Friends"))
                            }
                            Link(destination: URL(string: "voxii://notifications")!) {
                                widgetShortcut(icon: "bell.fill", title: widgetText(ru: "События", en: "Alerts"))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(widgetText(ru: "Активные диалоги", en: "Active Conversations"))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))

                        if let snapshot, !snapshot.contacts.isEmpty {
                            VStack(spacing: 8) {
                                ForEach(Array(snapshot.contacts.prefix(4))) { contact in
                                    Link(destination: URL(string: "voxii://messages/contact/\(contact.id)")!) {
                                        widgetChatRow(contact, style: .large)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } else {
                            widgetEmptyState(
                                title: widgetText(ru: "Пока пусто", en: "Still empty"),
                                subtitle: widgetText(ru: "После открытия приложения здесь появятся главные чаты.", en: "Your main chats will appear here after opening the app.")
                            )
                        }

                        if !additionalContacts.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(additionalContacts.prefix(3)) { contact in
                                    Link(destination: URL(string: "voxii://messages/contact/\(contact.id)")!) {
                                        widgetMiniContact(contact)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .frame(width: 180, alignment: .leading)
                }
            }
            .padding(18)
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private func dashboardSubtitle(_ snapshot: VoxiiInboxWidgetSnapshot?) -> String {
        guard let snapshot else {
            return widgetText(ru: "Ожидает первую синхронизацию", en: "Waiting for first sync")
        }
        if !snapshot.currentUsername.isEmpty {
            return widgetText(ru: "Аккаунт: \(snapshot.currentUsername)", en: "Account: \(snapshot.currentUsername)")
        }
        return widgetText(ru: "Сводка по чатам и друзьям", en: "Chat and friends overview")
    }

    private func priorityHeadline(_ contact: VoxiiInboxWidgetContact) -> String {
        if contact.unreadCount > 0 {
            return widgetText(ru: "\(contact.unreadCount) новых сообщений", en: "\(contact.unreadCount) new messages")
        }
        if contact.isOnline {
            return widgetText(ru: "Готов к диалогу прямо сейчас", en: "Ready to chat right now")
        }
        return widgetText(ru: "Быстрый переход в переписку", en: "Quick access to the conversation")
    }
}

private enum VoxiiChatRowStyle {
    case medium
    case large
}

private enum VoxiiWidgetPanelProminence {
    case normal
    case primary
}

private var widgetBackground: some View {
    ZStack {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.07, blue: 0.11),
                Color(red: 0.03, green: 0.04, blue: 0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        RadialGradient(
            colors: [
                Color(red: 0.33, green: 0.54, blue: 1.0).opacity(0.22),
                .clear
            ],
            center: .topLeading,
            startRadius: 8,
            endRadius: 220
        )

        Ellipse()
            .fill(Color.white.opacity(0.12))
            .frame(width: 180, height: 92)
            .blur(radius: 34)
            .offset(x: -42, y: -88)

        RadialGradient(
            colors: [
                Color(red: 0.19, green: 0.84, blue: 0.92).opacity(0.14),
                .clear
            ],
            center: .bottomTrailing,
            startRadius: 20,
            endRadius: 180
        )

        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.white.opacity(0.045))

        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.10),
                        Color.white.opacity(0.02),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.18),
                        Color.white.opacity(0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.1
            )

        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
            .padding(1)
    }
    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
}

private func widgetPanel(prominence: VoxiiWidgetPanelProminence) -> some View {
    let topOpacity = prominence == .primary ? 0.16 : 0.11
    let baseOpacity = prominence == .primary ? 0.10 : 0.07
    let shadowOpacity = prominence == .primary ? 0.18 : 0.12

    return RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(
            LinearGradient(
                colors: [
                    Color.white.opacity(baseOpacity),
                    Color.white.opacity(baseOpacity * 0.55)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(topOpacity),
                            Color.white.opacity(0.03),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(prominence == .primary ? 0.20 : 0.12),
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                .padding(1)
        )
        .shadow(color: Color.black.opacity(shadowOpacity), radius: prominence == .primary ? 18 : 10, x: 0, y: 6)
}

private func widgetHeader(title: String, subtitle: String, date: Date?, compact: Bool = false) -> some View {
    HStack(alignment: .center, spacing: 10) {
        widgetBrandMark(size: compact ? 28 : 30)

        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: compact ? 14 : 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: compact ? 10 : 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.66))
                .lineLimit(2)
        }

        Spacer(minLength: 0)

        if let date {
            Text(timeString(from: date))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.76))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(widgetCapsuleSurface(prominence: compact ? .normal : .primary))
        }
    }
}

private func widgetCapsuleSurface(prominence: VoxiiWidgetPanelProminence) -> some View {
    let fillOpacity = prominence == .primary ? 0.12 : 0.08
    return Capsule(style: .continuous)
        .fill(
            LinearGradient(
                colors: [
                    Color.white.opacity(fillOpacity),
                    Color.white.opacity(fillOpacity * 0.55)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(prominence == .primary ? 0.16 : 0.10), lineWidth: 0.9)
        )
}

private func widgetMetric(icon: String, value: String, label: String) -> some View {
    HStack(spacing: 6) {
        Image(systemName: icon)
            .font(.system(size: 10, weight: .bold))
        Text(value)
            .font(.system(size: 11, weight: .black, design: .rounded))
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.7))
    }
    .foregroundStyle(.white.opacity(0.86))
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(widgetCapsuleSurface(prominence: .normal))
}

private func widgetActionChip(icon: String, title: String) -> some View {
    HStack(spacing: 6) {
        Image(systemName: icon)
            .font(.system(size: 10, weight: .bold))
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .rounded))
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(widgetCapsuleSurface(prominence: .primary))
}

private func widgetShortcut(icon: String, title: String) -> some View {
    VStack(spacing: 6) {
        Image(systemName: icon)
            .font(.system(size: 13, weight: .bold))
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .lineLimit(1)
    }
    .foregroundStyle(.white)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 10)
    .background(widgetPanel(prominence: .normal))
}

private func widgetStatusBadge(icon: String, text: String) -> some View {
    HStack(spacing: 6) {
        Image(systemName: icon)
            .font(.system(size: 10, weight: .bold))
        Text(text)
            .font(.system(size: 10, weight: .black, design: .rounded))
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 9)
    .padding(.vertical, 7)
    .background(widgetCapsuleSurface(prominence: .normal))
}

private func widgetInlineTag(icon: String, title: String) -> some View {
    HStack(spacing: 6) {
        Image(systemName: icon)
            .font(.system(size: 9, weight: .bold))
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .rounded))
    }
    .foregroundStyle(.white.opacity(0.82))
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(widgetCapsuleSurface(prominence: .normal))
}

private func widgetEmptyState(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
        Text(title)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
        Text(subtitle)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.68))
            .lineLimit(3)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(widgetPanel(prominence: .normal))
}

private func widgetChatRow(_ contact: VoxiiInboxWidgetContact, style: VoxiiChatRowStyle) -> some View {
    HStack(spacing: 10) {
        widgetAvatar(contact, size: style == .large ? 40 : 38)

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(contact.username)
                    .font(.system(size: style == .large ? 14 : 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if contact.isFriend {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.42))
                }
            }

            Text(contactSecondaryLine(contact))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.64))
                .lineLimit(1)
        }

        Spacer(minLength: 6)

        if contact.unreadCount > 0 {
            Text(contact.unreadCount > 99 ? "99+" : "\(contact.unreadCount)")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.36, green: 0.56, blue: 1.0).opacity(0.96),
                                    Color(red: 0.28, green: 0.76, blue: 1.0).opacity(0.88)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                        )
                )
        } else {
            Image(systemName: contact.isOnline ? "dot.radiowaves.left.and.right" : "arrow.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(contact.isOnline ? Color(red: 0.38, green: 0.92, blue: 0.62) : .white.opacity(0.55))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                        )
                )
        }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, style == .large ? 10 : 9)
    .background(widgetPanel(prominence: .normal))
}

private func widgetMiniContact(_ contact: VoxiiInboxWidgetContact) -> some View {
    VStack(spacing: 6) {
        widgetAvatar(contact, size: 34)
        Text(String(contact.username.prefix(8)))
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
    .background(widgetPanel(prominence: .normal))
}

private func widgetAvatar(_ contact: VoxiiInboxWidgetContact, size: CGFloat) -> some View {
    ZStack(alignment: .bottomTrailing) {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.24),
                        Color.white.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.24),
                                Color.white.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .overlay(
                Text(String(contact.avatarText.prefix(1)).uppercased())
                    .font(.system(size: max(12, size * 0.38), weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            )
            .shadow(color: Color.black.opacity(0.14), radius: 10, x: 0, y: 4)

        Circle()
            .fill(contact.isOnline ? Color(red: 0.38, green: 0.92, blue: 0.62) : Color.white.opacity(0.24))
            .frame(width: max(8, size * 0.24), height: max(8, size * 0.24))
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(0.4), lineWidth: 1.5)
            )
    }
}

private func widgetBrandMark(size: CGFloat) -> some View {
    ZStack {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.35, green: 0.55, blue: 1.0),
                        Color(red: 0.22, green: 0.82, blue: 0.96)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color(red: 0.25, green: 0.55, blue: 1.0).opacity(0.28), radius: 14, x: 0, y: 6)

        Text("V")
            .font(.system(size: size * 0.46, weight: .black, design: .rounded))
            .foregroundStyle(.white)
    }
}

private func contactSecondaryLine(_ contact: VoxiiInboxWidgetContact) -> String {
    if contact.unreadCount > 0 {
        return widgetText(ru: "Непрочитанные сообщения", en: "Unread messages")
    }
    if contact.isOnline {
        return widgetText(ru: "Сейчас в сети", en: "Online now")
    }
    if contact.isFriend {
        return widgetText(ru: "Друг в Voxii", en: "Friend in Voxii")
    }
    return widgetText(ru: "Открыть чат", en: "Open chat")
}

private func unreadCaption(for count: Int) -> String {
    if count == 0 {
        return widgetText(ru: "непропущенных сообщений нет", en: "all caught up")
    }
    if count == 1 {
        return widgetText(ru: "непрочитанное", en: "unread")
    }
    return widgetText(ru: "непрочитанных", en: "unread")
}

private func widgetText(ru: String, en: String) -> String {
    let stored = UserDefaults(suiteName: VoxiiWidgetShared.appGroupID)?.string(forKey: "voxii_language")?.lowercased()
    if let stored, !stored.isEmpty {
        return stored == "ru" ? ru : en
    }
    let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
    return preferred.hasPrefix("ru") ? ru : en
}

private func timeString(from date: Date?) -> String {
    guard let date else {
        return ""
    }
    return date.formatted(date: .omitted, time: .shortened)
}
