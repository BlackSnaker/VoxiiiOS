import SwiftUI
import Combine
import WebKit

struct MessengerHomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var appearance: VoxiiAppearance
    @State private var selectedTab: HomeTab = .messages
    @State private var incomingCall: IncomingCallPayload?
    @State private var callIDsAnsweredBySystem: Set<String> = []
    @State private var notifiedMessageNotificationIDs: Set<Int> = []
    @State private var didPrimeMessageNotificationTracker = false
    @State private var isPollingMessageNotifications = false

    private let messageNotificationRefreshTimer = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    enum HomeTab: Hashable {
        case messages
        case friends
        case news
        case notifications
        case settings
    }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                DMInboxView()
                    .environmentObject(session)
                    .tabItem {
                        Label(appearance.t("tab.messages"), systemImage: "message.fill")
                    }
                    .tag(HomeTab.messages)

                FriendsHubView()
                    .environmentObject(session)
                    .tabItem {
                        Label(appearance.t("tab.friends"), systemImage: "person.2.fill")
                    }
                    .tag(HomeTab.friends)

                NewsChannelView()
                    .environmentObject(session)
                    .tabItem {
                        Label(appearance.t("tab.news"), systemImage: "newspaper.fill")
                    }
                    .tag(HomeTab.news)

                NotificationsCenterView()
                    .environmentObject(session)
                    .tabItem {
                        Label(appearance.t("tab.notifications"), systemImage: "bell.fill")
                    }
                    .tag(HomeTab.notifications)

                SettingsHomeView()
                    .environmentObject(session)
                    .tabItem {
                        Label(appearance.t("tab.settings"), systemImage: "slider.horizontal.3")
                    }
                    .tag(HomeTab.settings)
            }
            .tint(VoxiiTheme.accent)

            if let token = session.token, session.currentUser != nil {
                IncomingCallListenerContainer(
                    baseServerURL: session.serverURL,
                    token: token
                ) { payload in
                    VoxiiCallKitManager.shared.reportIncomingCall(payload)
                }
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .id(incomingListenerID(token: token))
            }
        }
        .task {
            if let pendingAnswered = VoxiiCallKitManager.shared.consumePendingAnswerPayload() {
                callIDsAnsweredBySystem.insert(pendingAnswered.id)
                incomingCall = pendingAnswered
            } else if let pendingIncoming = VoxiiCallKitManager.shared.consumePendingIncomingPayload() {
                incomingCall = pendingIncoming
            }
        }
        .task(id: messageNotificationTrackerID) {
            await primeMessageNotificationTracker()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .voxiiIncomingCallDidArrive)
                .compactMap { $0.object as? IncomingCallPayload }
        ) { payload in
            guard incomingCall == nil else {
                return
            }
            incomingCall = payload
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .voxiiIncomingCallAnswerRequested)
                .compactMap { $0.object as? IncomingCallPayload }
        ) { payload in
            callIDsAnsweredBySystem.insert(payload.id)
            incomingCall = payload
        }
        .onReceive(messageNotificationRefreshTimer) { _ in
            guard scenePhase == .active else {
                return
            }
            Task {
                await pollIncomingMessageNotifications()
            }
        }
        .fullScreenCover(item: $incomingCall) { payload in
            let autoAcceptIncoming = callIDsAnsweredBySystem.contains(payload.id)
            VideoCallView(
                config: .init(
                    baseServerURL: session.serverURL,
                    token: session.token ?? "",
                    selfUser: session.currentUser,
                    peer: APIUser(
                        id: payload.callerId,
                        username: payload.callerUsername,
                        email: nil,
                        avatar: payload.callerAvatar,
                        status: "online"
                    ),
                    callType: payload.callType,
                    mode: .incoming,
                    initialIncomingSocketId: payload.callerSocketId,
                    initialIncomingUserId: payload.callerId,
                    initialIncomingUsername: payload.callerUsername,
                    initialIncomingAvatar: payload.callerAvatar,
                    autoAcceptIncoming: autoAcceptIncoming
                )
            ) {
                callIDsAnsweredBySystem.remove(payload.id)
                VoxiiCallKitManager.shared.endCall(eventID: payload.id)
                incomingCall = nil
            }
            .environmentObject(appearance)
        }
    }

    private func incomingListenerID(token: String) -> String {
        let userID = session.currentUser?.id ?? 0
        return "\(session.serverURL)|\(token)|\(userID)"
    }

    private var messageNotificationTrackerID: String {
        let userID = session.currentUser?.id ?? 0
        let tokenMarker = session.token ?? "no-token"
        return "\(session.serverURL)|\(tokenMarker)|\(userID)"
    }

    private func primeMessageNotificationTracker() async {
        guard session.isAuthenticated else {
            notifiedMessageNotificationIDs.removeAll()
            didPrimeMessageNotificationTracker = false
            return
        }

        do {
            let unread = try await session.fetchUnreadNotifications()
            notifiedMessageNotificationIDs = Set(
                unread.notifications
                    .filter(isTrackableUnreadMessageNotification)
                    .map(\.id)
            )
            didPrimeMessageNotificationTracker = true
        } catch {
            // Start tracking even if first request fails to avoid noisy retries.
            notifiedMessageNotificationIDs.removeAll()
            didPrimeMessageNotificationTracker = true
        }
    }

    private func pollIncomingMessageNotifications() async {
        guard session.isAuthenticated else {
            return
        }

        guard didPrimeMessageNotificationTracker else {
            await primeMessageNotificationTracker()
            return
        }

        guard !isPollingMessageNotifications else {
            return
        }
        isPollingMessageNotifications = true
        defer { isPollingMessageNotifications = false }

        do {
            let unread = try await session.fetchUnreadNotifications()
            let unreadMessages = unread.notifications
                .filter(isTrackableUnreadMessageNotification)
                .sorted { lhs, rhs in
                    let lhsDate = VoxiiDate.date(lhs.createdAt) ?? .distantPast
                    let rhsDate = VoxiiDate.date(rhs.createdAt) ?? .distantPast
                    if lhsDate == rhsDate {
                        return lhs.id < rhs.id
                    }
                    return lhsDate < rhsDate
                }

            var knownIDs = notifiedMessageNotificationIDs
            for item in unreadMessages {
                guard !knownIDs.contains(item.id) else {
                    continue
                }
                knownIDs.insert(item.id)
                VoxiiPushNotifications.scheduleForegroundMessageNotification(
                    messageID: String(item.id),
                    title: messageNotificationTitle(for: item),
                    body: messageNotificationBody(for: item)
                )
            }

            if knownIDs.count > 600 {
                let activeUnreadIDs = Set(unreadMessages.map(\.id))
                knownIDs.formIntersection(activeUnreadIDs)
            }

            notifiedMessageNotificationIDs = knownIDs
        } catch {
            // Ignore transient polling failures.
        }
    }

    private func isTrackableUnreadMessageNotification(_ item: NotificationItem) -> Bool {
        guard !item.read else {
            return false
        }
        if let currentUserID = session.currentUser?.id,
           let fromUserID = item.fromUserId,
           fromUserID == currentUserID {
            return false
        }

        let type = item.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if type == "message" || type == "new-message" || type == "new_message" || type == "direct_message" || type == "dm" {
            return true
        }
        return type.contains("message") || type.contains("dm")
    }

    private func messageNotificationTitle(for item: NotificationItem) -> String {
        let sender = item.fromUsername?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return sender.isEmpty ? "Voxii" : sender
    }

    private func messageNotificationBody(for item: NotificationItem) -> String {
        let text = item.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "You have a new message" : text
    }
}

private struct DMInboxView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var appearance: VoxiiAppearance

    @State private var users: [APIUser] = []
    @State private var friendIDs: Set<Int> = []
    @State private var unreadByUser: [Int: Int] = [:]
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                VoxiiBackground()

                VStack(spacing: 12) {
                    header
                    search
                    content
                }
                .padding(14)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await loadData()
            }
            .alert("Error", isPresented: errorBinding) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VoxiiAvatarView(
                text: session.currentUser?.username ?? "V",
                isOnline: true,
                size: 42
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("Direct Messages")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(VoxiiTheme.text)
                Text("Voxii")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(VoxiiTheme.muted)
            }

            Spacer()

            Button {
                Task { await loadData() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .bold))
            }
            .buttonStyle(VoxiiGradientButtonStyle(isCompact: true, variant: .neutral))
            .disabled(isLoading)
        }
        .voxiiCard(cornerRadius: 18, padding: 14)
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(VoxiiTheme.muted)
            TextField("Find or start a conversation", text: $searchText)
                .foregroundStyle(VoxiiTheme.text)
        }
        .voxiiInput()
    }

    private var content: some View {
        Group {
            if isLoading && users.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(VoxiiTheme.accent)
                    Text("Loading conversations...")
                        .foregroundStyle(VoxiiTheme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .voxiiCard(cornerRadius: 18, padding: 18)
            } else if filteredUsers.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(VoxiiTheme.muted)
                    Text("No matching users")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(VoxiiTheme.text)
                    Text("Try another search query.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(VoxiiTheme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .voxiiCard(cornerRadius: 18, padding: 18)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredUsers) { user in
                            NavigationLink {
                                ChatView(peer: user)
                                    .environmentObject(session)
                            } label: {
                                DMContactRow(
                                    user: user,
                                    isFriend: friendIDs.contains(user.id),
                                    unreadCount: unreadByUser[user.id] ?? 0
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .refreshable {
                    await loadData()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var filteredUsers: [APIUser] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        let sorted = users.sorted { lhs, rhs in
            let lhsFriend = friendIDs.contains(lhs.id)
            let rhsFriend = friendIDs.contains(rhs.id)
            if lhsFriend != rhsFriend {
                return lhsFriend
            }

            let lhsOnline = lhs.status?.lowercased() == "online"
            let rhsOnline = rhs.status?.lowercased() == "online"
            if lhsOnline != rhsOnline {
                return lhsOnline
            }

            return lhs.username.localizedCaseInsensitiveCompare(rhs.username) == .orderedAscending
        }

        guard !trimmed.isEmpty else {
            return sorted
        }

        return sorted.filter { user in
            user.username.localizedCaseInsensitiveContains(trimmed) ||
            (user.email?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let usersTask = session.fetchUsers()
            async let friendsTask = session.fetchFriends()
            async let unreadTask = session.fetchUnreadNotifications()

            let (allUsers, friends, unread) = try await (usersTask, friendsTask, unreadTask)

            users = allUsers
            friendIDs = Set(friends.map(\.id))

            var unreadMap: [Int: Int] = [:]
            for item in unread.notifications where item.type == "message" {
                guard let fromUserId = item.fromUserId else {
                    continue
                }
                unreadMap[fromUserId, default: 0] += 1
            }
            unreadByUser = unreadMap
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct DMContactRow: View {
    let user: APIUser
    let isFriend: Bool
    let unreadCount: Int

    var body: some View {
        HStack(spacing: 12) {
            VoxiiAvatarView(
                text: user.avatar ?? user.username,
                isOnline: user.status?.lowercased() == "online",
                size: 44
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(user.username)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(VoxiiTheme.text)

                    if isFriend {
                        Text("Friend")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(VoxiiTheme.accent.opacity(0.28))
                            )
                            .foregroundStyle(.white)
                    }
                }

                HStack(spacing: 8) {
                    Text(user.status ?? "Offline")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(user.status?.lowercased() == "online" ? VoxiiTheme.online : VoxiiTheme.muted)

                    if let email = user.email, !email.isEmpty {
                        Text("•")
                            .foregroundStyle(VoxiiTheme.mutedSecondary)
                        Text(email)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(VoxiiTheme.muted)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if unreadCount > 0 {
                Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(VoxiiTheme.accentGradient)
                    )
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(VoxiiTheme.mutedSecondary)
        }
        .voxiiCard(cornerRadius: 14, padding: 12)
    }
}

private struct FriendsHubView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var appearance: VoxiiAppearance

    @State private var selectedTab: FriendsTab = .online
    @State private var friends: [FriendRequestUser] = []
    @State private var pendingRequests: [FriendRequestUser] = []
    @State private var allUsers: [APIUser] = []
    @State private var addSearch = ""
    @State private var requestedIDs: Set<Int> = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    enum FriendsTab: String, CaseIterable, Identifiable {
        case online = "Online"
        case all = "All"
        case pending = "Pending"
        case add = "Add Friend"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VoxiiBackground()

                VStack(spacing: 12) {
                    header
                    picker
                    bodyContent
                }
                .padding(14)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await loadData()
            }
            .alert("Error", isPresented: errorBinding) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(
                    Circle()
                        .fill(VoxiiTheme.accentGradient)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Friends")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(VoxiiTheme.text)
                Text("Manage online, pending and new requests")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(VoxiiTheme.muted)
            }

            Spacer()

            Button {
                Task { await loadData() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .bold))
            }
            .buttonStyle(VoxiiGradientButtonStyle(isCompact: true, variant: .neutral))
            .disabled(isLoading)
        }
        .voxiiCard(cornerRadius: 18, padding: 14)
    }

    private var picker: some View {
        Picker("Friends", selection: $selectedTab) {
            ForEach(FriendsTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(VoxiiTheme.glass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(VoxiiTheme.stroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch selectedTab {
        case .online:
            friendsListView(items: friends.filter { ($0.status ?? "").lowercased() == "online" }, emptyText: "No friends online")
        case .all:
            friendsListView(items: friends, emptyText: "No friends yet")
        case .pending:
            pendingListView
        case .add:
            addFriendsView
        }
    }

    private func friendsListView(items: [FriendRequestUser], emptyText: String) -> some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(VoxiiTheme.muted)
                    Text(emptyText)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(VoxiiTheme.text)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .voxiiCard(cornerRadius: 16, padding: 18)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(items) { friend in
                            FriendRow(
                                friend: friend,
                                onRemove: {
                                    Task { await removeFriend(friend.id) }
                                }
                            )
                            .environmentObject(session)
                        }
                    }
                }
                .refreshable {
                    await loadData()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var pendingListView: some View {
        Group {
            if pendingRequests.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(VoxiiTheme.muted)
                    Text("No pending requests")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(VoxiiTheme.text)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .voxiiCard(cornerRadius: 16, padding: 18)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(pendingRequests) { user in
                            HStack(spacing: 12) {
                                VoxiiAvatarView(
                                    text: user.avatar ?? user.username,
                                    isOnline: user.status?.lowercased() == "online",
                                    size: 42
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(user.username)
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundStyle(VoxiiTheme.text)
                                    Text(user.email ?? "No email")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(VoxiiTheme.muted)
                                }

                                Spacer()

                                Button("Accept") {
                                    Task { await acceptRequest(user.id) }
                                }
                                .buttonStyle(VoxiiGradientButtonStyle(isCompact: true))

                                Button("Reject") {
                                    Task { await rejectRequest(user.id) }
                                }
                                .buttonStyle(VoxiiGradientButtonStyle(isCompact: true, variant: .danger))
                            }
                            .voxiiCard(cornerRadius: 14, padding: 12)
                        }
                    }
                }
                .refreshable {
                    await loadData()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var addFriendsView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(VoxiiTheme.muted)
                TextField("Search username", text: $addSearch)
                    .foregroundStyle(VoxiiTheme.text)
            }
            .voxiiInput()

            if addCandidates.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(VoxiiTheme.muted)
                    Text("Type username to find users")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(VoxiiTheme.text)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .voxiiCard(cornerRadius: 16, padding: 18)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(addCandidates) { user in
                            HStack(spacing: 12) {
                                VoxiiAvatarView(
                                    text: user.avatar ?? user.username,
                                    isOnline: user.status?.lowercased() == "online",
                                    size: 42
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(user.username)
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundStyle(VoxiiTheme.text)

                                    Text(user.email ?? "No email")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(VoxiiTheme.muted)
                                }

                                Spacer()

                                if requestedIDs.contains(user.id) {
                                    Text("Requested")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(VoxiiTheme.online)
                                } else {
                                    Button("Add") {
                                        Task { await sendRequest(user.id) }
                                    }
                                    .buttonStyle(VoxiiGradientButtonStyle(isCompact: true))
                                }
                            }
                            .voxiiCard(cornerRadius: 14, padding: 12)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var addCandidates: [APIUser] {
        let trimmed = addSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        let friendIDs = Set(friends.map(\.id))
        let pendingIDs = Set(pendingRequests.map(\.id))

        return allUsers
            .filter { user in
                guard user.id != session.currentUser?.id else {
                    return false
                }
                guard !friendIDs.contains(user.id), !pendingIDs.contains(user.id) else {
                    return false
                }
                return user.username.localizedCaseInsensitiveContains(trimmed)
                    || (user.email?.localizedCaseInsensitiveContains(trimmed) ?? false)
            }
            .sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let friendsTask = session.fetchFriends()
            async let pendingTask = session.fetchPendingFriends()
            async let usersTask = session.fetchUsers()

            let (loadedFriends, loadedPending, loadedUsers) = try await (friendsTask, pendingTask, usersTask)
            friends = loadedFriends
            pendingRequests = loadedPending
            allUsers = loadedUsers
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func sendRequest(_ userID: Int) async {
        do {
            try await session.sendFriendRequest(friendID: userID)
            requestedIDs.insert(userID)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func acceptRequest(_ userID: Int) async {
        do {
            try await session.acceptFriendRequest(friendID: userID)
            await loadData()
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func rejectRequest(_ userID: Int) async {
        do {
            try await session.rejectFriendRequest(friendID: userID)
            await loadData()
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func removeFriend(_ userID: Int) async {
        do {
            try await session.removeFriend(friendID: userID)
            await loadData()
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct FriendRow: View {
    @EnvironmentObject private var session: SessionStore

    let friend: FriendRequestUser
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VoxiiAvatarView(
                text: friend.avatar ?? friend.username,
                isOnline: friend.status?.lowercased() == "online",
                size: 42
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(friend.username)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(VoxiiTheme.text)

                Text(friend.status ?? "Offline")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(friend.status?.lowercased() == "online" ? VoxiiTheme.online : VoxiiTheme.muted)
            }

            Spacer()

            NavigationLink {
                ChatView(peer: friend.asAPIUser)
                    .environmentObject(session)
            } label: {
                Image(systemName: "message.fill")
                    .font(.system(size: 13, weight: .bold))
            }
            .buttonStyle(VoxiiGradientButtonStyle(isCompact: true, variant: .neutral))

            Button {
                onRemove()
            } label: {
                Image(systemName: "person.badge.minus")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(VoxiiGradientButtonStyle(isCompact: true, variant: .danger))
        }
        .voxiiCard(cornerRadius: 14, padding: 12)
    }
}

private struct NewsChannelView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var appearance: VoxiiAppearance

    @State private var channel: ChannelModel?
    @State private var channelMessages: [ChannelMessage] = []
    @State private var staticNews: [StaticNewsItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let refreshTimer = Timer.publish(every: 8, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                VoxiiBackground()

                VStack(spacing: 12) {
                    header
                    messagesList
                    readOnlyNotice
                }
                .padding(14)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await loadData()
            }
            .onReceive(refreshTimer) { _ in
                guard scenePhase == .active else {
                    return
                }
                Task { await refreshMessagesOnly() }
            }
            .alert("Error", isPresented: errorBinding) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(VoxiiTheme.accentGradient)
                    .frame(width: 42, height: 42)
                Image(systemName: "newspaper.fill")
                    .foregroundStyle(.white)
                    .font(.system(size: 16, weight: .bold))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(channel?.name ?? "News")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(VoxiiTheme.text)
                Text(channelSubtitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(VoxiiTheme.muted)
            }

            Spacer()

            Button {
                Task { await loadData() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .bold))
            }
            .buttonStyle(VoxiiGradientButtonStyle(isCompact: true, variant: .neutral))
            .disabled(isLoading)
        }
        .voxiiCard(cornerRadius: 18, padding: 14)
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if timelineItems.isEmpty && !isLoading {
                        VStack(spacing: 10) {
                            Image(systemName: "newspaper")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(VoxiiTheme.muted)
                            Text("No news messages yet")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(VoxiiTheme.text)
                        }
                        .frame(maxWidth: .infinity)
                        .voxiiCard(cornerRadius: 16, padding: 18)
                    } else {
                        ForEach(timelineItems) { item in
                            switch item {
                            case .staticNews(let news):
                                NewsStaticRow(news: news)
                                    .id(item.id)
                            case .channel(let message):
                                NewsMessageRow(
                                    message: message,
                                    isMine: message.senderID == session.currentUser?.id
                                )
                                .id(item.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
            }
            .onChange(of: timelineItems.count) { _, _ in
                guard let lastID = timelineItems.last?.id else {
                    return
                }
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
        .voxiiCard(cornerRadius: 18, padding: 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var readOnlyNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(VoxiiTheme.accentLight)
            Text("News channel is read-only")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(VoxiiTheme.muted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(VoxiiTheme.glass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(VoxiiTheme.stroke, lineWidth: 1)
        )
    }

    private var timelineItems: [NewsTimelineItem] {
        let dynamicItems = channelMessages.map(NewsTimelineItem.channel)
        let staticItems = staticNews.map(NewsTimelineItem.staticNews)
        return (dynamicItems + staticItems).sorted { lhs, rhs in
            let lhsDate = VoxiiDate.date(lhs.createdAt) ?? .distantPast
            let rhsDate = VoxiiDate.date(rhs.createdAt) ?? .distantPast
            if lhsDate == rhsDate {
                return lhs.id < rhs.id
            }
            return lhsDate < rhsDate
        }
    }

    private var channelSubtitle: String {
        if let count = channel?.subscriberCount {
            return "\(count) subscribers"
        }
        return "System channel"
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loadedChannel = try await resolveSystemChannel()
            channel = loadedChannel

            async let dynamicMessagesTask = session.fetchChannelMessages(channelID: loadedChannel.id)
            async let staticNewsTask = loadStaticNews()

            let fetchedMessages = (try? await dynamicMessagesTask) ?? []
            let fetchedStaticNews = await staticNewsTask

            if fetchedMessages != channelMessages {
                channelMessages = fetchedMessages
            }
            if fetchedStaticNews != staticNews {
                staticNews = fetchedStaticNews
            }
            errorMessage = nil
        } catch {
            let fallbackNews = await loadStaticNews()
            if fallbackNews != staticNews {
                staticNews = fallbackNews
            }
            if channelMessages.isEmpty && staticNews.isEmpty {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            } else {
                errorMessage = nil
            }
        }
    }

    private func resolveSystemChannel() async throws -> ChannelModel {
        if let direct = try? await session.fetchSystemChannel() {
            return direct
        }

        let channels = try await session.fetchChannels()
        if let matched = channels.first(where: isSystemChannel) {
            return matched
        }

        throw APIClientError.server("System channel not found.")
    }

    private func isSystemChannel(_ channel: ChannelModel) -> Bool {
        if (channel.isSystem ?? 0) != 0 {
            return true
        }

        if channel.type?.lowercased() == "system" {
            return true
        }

        let normalizedName = channel.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedName.contains("news") || normalizedName.contains("новост")
    }

    private func refreshMessagesOnly() async {
        guard let channelID = channel?.id else {
            return
        }

        let fetchedMessages = (try? await session.fetchChannelMessages(channelID: channelID)) ?? channelMessages
        if fetchedMessages != channelMessages {
            channelMessages = fetchedMessages
        }

        let fetchedStaticNews = await loadStaticNews()
        if fetchedStaticNews != staticNews {
            staticNews = fetchedStaticNews
        }
    }

    private func loadStaticNews() async -> [StaticNewsItem] {
        guard let baseURL = VoxiiURLBuilder.normalizeBaseURL(session.serverURL) else {
            return []
        }

        for url in staticNewsCandidateURLs(baseURL: baseURL) {
            if let items = await fetchStaticNews(from: url), !items.isEmpty {
                return items
            }
        }

        for url in changelogCandidateURLs(baseURL: baseURL) {
            if let items = await fetchStaticNewsFromChangelog(from: url), !items.isEmpty {
                return items
            }
        }

        return []
    }

    private func fetchStaticNews(from url: URL) async -> [StaticNewsItem]? {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = session.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                return nil
            }

            if let payload = try? JSONDecoder().decode(StaticNewsPayload.self, from: data), !payload.news.isEmpty {
                return payload.news
            }
            if let bareList = try? JSONDecoder().decode([StaticNewsItem].self, from: data), !bareList.isEmpty {
                return bareList
            }
            let fallbackList = decodeStaticNewsFallback(from: data)
            if !fallbackList.isEmpty {
                return fallbackList
            }
            return []
        } catch {
            return nil
        }
    }

    private func fetchStaticNewsFromChangelog(from url: URL) async -> [StaticNewsItem]? {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 20
        request.setValue("text/markdown,text/plain;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        if let token = session.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let markdown = String(data: data, encoding: .utf8),
                  !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            let parsed = parseNewsFromChangelog(markdown)
            return parsed.isEmpty ? nil : parsed
        } catch {
            return nil
        }
    }

    private func parseNewsFromChangelog(_ markdown: String) -> [StaticNewsItem] {
        let versionPattern = #"^## \[([^\]]+)\] - (\d{4}-\d{2}-\d{2})"#
        guard let versionRegex = try? NSRegularExpression(pattern: versionPattern) else {
            return []
        }

        let lines = markdown.components(separatedBy: .newlines)
        var items: [StaticNewsItem] = []

        var currentVersion: String?
        var currentDate: String?
        var currentChanges: [String] = []
        var autoID = 1

        func commitCurrent() {
            guard let version = currentVersion,
                  let date = currentDate else {
                return
            }
            let title = "Версия \(version)"
            items.append(
                StaticNewsItem(
                    id: String(autoID),
                    title: title,
                    version: version,
                    date: date,
                    changes: currentChanges
                )
            )
            autoID += 1
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else {
                continue
            }

            let fullRange = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = versionRegex.firstMatch(in: line, options: [], range: fullRange),
               let versionRange = Range(match.range(at: 1), in: line),
               let dateRange = Range(match.range(at: 2), in: line) {
                commitCurrent()
                currentVersion = String(line[versionRange])
                currentDate = String(line[dateRange])
                currentChanges = []
                continue
            }

            guard currentVersion != nil else {
                continue
            }

            if line.hasPrefix("- ") {
                let change = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !change.isEmpty && !change.hasPrefix("**") {
                    currentChanges.append(change)
                }
            }
        }

        commitCurrent()
        return items
    }

    private func decodeStaticNewsFallback(from data: Data) -> [StaticNewsItem] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        let rawItems: [Any]
        if let object = json as? [String: Any] {
            rawItems = (object["news"] as? [Any])
                ?? (object["items"] as? [Any])
                ?? (object["updates"] as? [Any])
                ?? (object["data"] as? [Any])
                ?? []
        } else if let array = json as? [Any] {
            rawItems = array
        } else {
            rawItems = []
        }

        return rawItems.compactMap { item in
            guard let object = item as? [String: Any],
                  let itemData = try? JSONSerialization.data(withJSONObject: object),
                  let decoded = try? JSONDecoder().decode(StaticNewsItem.self, from: itemData) else {
                return nil
            }
            return decoded
        }
    }

    private func staticNewsCandidateURLs(baseURL: URL) -> [URL] {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return [baseURL.appending(path: "news.json")]
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let candidatePaths: [String]
        if basePath.isEmpty {
            candidatePaths = [
                "/news.json",
                "/dist/news.json",
                "/client/news.json",
                "/client/dist/news.json",
                "/assets/news.json",
                "/public/news.json",
                "/static/news.json"
            ]
        } else {
            candidatePaths = [
                "/\(basePath)/news.json",
                "/news.json",
                "/\(basePath)/dist/news.json",
                "/dist/news.json",
                "/\(basePath)/client/news.json",
                "/client/news.json",
                "/\(basePath)/client/dist/news.json",
                "/client/dist/news.json",
                "/\(basePath)/assets/news.json",
                "/assets/news.json",
                "/\(basePath)/public/news.json",
                "/public/news.json"
            ]
        }

        var results: [URL] = []
        var seen = Set<String>()
        for path in candidatePaths {
            components.path = path
            components.query = nil
            components.fragment = nil
            guard let url = components.url else {
                continue
            }
            if seen.insert(url.absoluteString).inserted {
                results.append(url)
            }
        }

        return results
    }

    private func changelogCandidateURLs(baseURL: URL) -> [URL] {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return []
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let candidatePaths: [String]
        if basePath.isEmpty {
            candidatePaths = [
                "/CHANGELOG.md",
                "/changelog.md",
                "/client/CHANGELOG.md",
                "/client/changelog.md",
                "/dist/CHANGELOG.md",
                "/dist/changelog.md"
            ]
        } else {
            candidatePaths = [
                "/\(basePath)/CHANGELOG.md",
                "/\(basePath)/changelog.md",
                "/CHANGELOG.md",
                "/changelog.md",
                "/\(basePath)/client/CHANGELOG.md",
                "/client/CHANGELOG.md",
                "/\(basePath)/dist/CHANGELOG.md",
                "/dist/CHANGELOG.md"
            ]
        }

        var results: [URL] = []
        var seen = Set<String>()
        for path in candidatePaths {
            components.path = path
            components.query = nil
            components.fragment = nil
            guard let url = components.url else {
                continue
            }
            if seen.insert(url.absoluteString).inserted {
                results.append(url)
            }
        }
        return results
    }
}

private struct NewsMessageRow: View {
    let message: ChannelMessage
    let isMine: Bool

    var body: some View {
        HStack {
            if isMine {
                Spacer(minLength: 40)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(message.username ?? "Unknown")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(isMine ? Color.white.opacity(0.86) : VoxiiTheme.accentLight)

                    if message.edited {
                        Text("(edited)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(isMine ? Color.white.opacity(0.7) : VoxiiTheme.muted)
                    }

                    Spacer(minLength: 0)

                    Text(VoxiiDate.shortTime(message.createdAt))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(isMine ? Color.white.opacity(0.76) : VoxiiTheme.muted)
                }

                if let reply = message.replyTo {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("↪ \(reply.author ?? "Unknown")")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(isMine ? Color.white.opacity(0.86) : VoxiiTheme.accentLight)
                        Text(reply.text ?? "[attachment]")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(isMine ? Color.white.opacity(0.78) : VoxiiTheme.muted)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(isMine ? 0.14 : 0.05))
                    )
                }

                Text(message.content)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(isMine ? .white : VoxiiTheme.text)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: VoxiiTheme.radiusM, style: .continuous)
                    .fill(isMine ? AnyShapeStyle(VoxiiTheme.accentGradient) : AnyShapeStyle(VoxiiTheme.glass))
            )
            .overlay(
                RoundedRectangle(cornerRadius: VoxiiTheme.radiusM, style: .continuous)
                    .stroke(isMine ? Color.white.opacity(0.15) : VoxiiTheme.stroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.24), radius: 10, x: 0, y: 6)

            if !isMine {
                Spacer(minLength: 40)
            }
        }
    }
}

private struct NewsStaticRow: View {
    let news: StaticNewsItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Система")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#FFB54A") ?? VoxiiTheme.accentLight)

                    Text(news.versionLabel)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill((Color(hex: "#FFB54A") ?? VoxiiTheme.accent).opacity(0.22))
                        )
                        .foregroundStyle(Color(hex: "#FFCC78") ?? VoxiiTheme.accentLight)

                    Spacer(minLength: 0)

                    Text(VoxiiDate.shortDateTime(news.createdAt))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(VoxiiTheme.muted)
                }

                Text(news.renderedText)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(VoxiiTheme.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: VoxiiTheme.radiusM, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                (Color(hex: "#2A1905") ?? Color.orange.opacity(0.22)),
                                (Color(hex: "#3C2509") ?? Color.orange.opacity(0.14))
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: VoxiiTheme.radiusM, style: .continuous)
                    .stroke((Color(hex: "#FFB54A") ?? VoxiiTheme.accent).opacity(0.38), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.24), radius: 10, x: 0, y: 6)

            Spacer(minLength: 40)
        }
    }
}

private struct StaticNewsPayload: Decodable {
    let news: [StaticNewsItem]
}

private struct StaticNewsItem: Decodable, Hashable, Identifiable {
    let id: String
    let title: String
    let version: String?
    let date: String
    let changes: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case headline
        case version
        case date
        case content
        case text
        case body
        case createdAt = "created_at"
        case createdAtCamel = "createdAt"
        case publishedAt = "published_at"
        case publishedAtCamel = "publishedAt"
        case updatedAt = "updated_at"
        case updatedAtCamel = "updatedAt"
        case changes
    }

    init(id: String, title: String, version: String?, date: String, changes: [String]) {
        self.id = id
        self.title = title
        self.version = version
        self.date = date
        self.changes = changes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let stringID = try container.decodeIfPresent(String.self, forKey: .id), !stringID.isEmpty {
            id = stringID
        } else if let intID = try container.decodeIfPresent(Int.self, forKey: .id) {
            id = String(intID)
        } else {
            let fallbackTitle = try container.decodeIfPresent(String.self, forKey: .title)
                ?? container.decodeIfPresent(String.self, forKey: .headline)
                ?? "news"
            let fallbackDate = try Self.decodeDate(from: container)
            id = "\(fallbackTitle)-\(fallbackDate)"
        }

        let decodedTitle = try container.decodeIfPresent(String.self, forKey: .title)
            ?? container.decodeIfPresent(String.self, forKey: .headline)

        version = try container.decodeIfPresent(String.self, forKey: .version)
        date = try Self.decodeDate(from: container)

        let decodedContent = try container.decodeIfPresent(String.self, forKey: .content)
            ?? container.decodeIfPresent(String.self, forKey: .text)
            ?? container.decodeIfPresent(String.self, forKey: .body)
            ?? ""

        let decodedChanges = try container.decodeIfPresent([String].self, forKey: .changes)
            ?? Self.extractChanges(from: decodedContent)

        if let decodedTitle, !decodedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = decodedTitle
        } else if let firstLineTitle = Self.extractTitle(from: decodedContent), !firstLineTitle.isEmpty {
            title = firstLineTitle
        } else {
            title = "Update"
        }

        changes = decodedChanges
    }

    var createdAt: String {
        let trimmed = date.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }
        return trimmed.contains("T") ? trimmed : "\(trimmed)T00:00:00Z"
    }

    var versionLabel: String {
        guard let version, !version.isEmpty else {
            return "news"
        }
        return "v\(version)"
    }

    var renderedText: String {
        let titleLine = "📢 \(title)"
        guard !changes.isEmpty else {
            return titleLine
        }
        let bulletLines = changes.map { "• \($0)" }.joined(separator: "\n")
        return "\(titleLine)\n\n\(bulletLines)"
    }

    private static func extractTitle(from content: String) -> String? {
        for rawLine in content.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            if line.hasPrefix("📢") {
                line = line.replacingOccurrences(of: "📢", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            }

            line = line.replacingOccurrences(of: "**", with: "")
            if line.hasPrefix("• ") || line.hasPrefix("- ") || line.hasPrefix("* ") {
                continue
            }

            if let markerRange = line.range(of: "(v", options: .caseInsensitive),
               line.hasSuffix(")") {
                line = String(line[..<markerRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if !line.isEmpty {
                return line
            }
        }
        return nil
    }

    private static func extractChanges(from content: String) -> [String] {
        var items: [String] = []
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            if line.hasPrefix("• ") {
                items.append(String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines))
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                items.append(String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines))
                continue
            }
        }
        return items
    }

    private static func decodeDate(from container: KeyedDecodingContainer<CodingKeys>) throws -> String {
        if let value = try container.decodeIfPresent(String.self, forKey: .date) {
            return value
        }
        if let value = try container.decodeIfPresent(String.self, forKey: .createdAt) {
            return value
        }
        if let value = try container.decodeIfPresent(String.self, forKey: .createdAtCamel) {
            return value
        }
        if let value = try container.decodeIfPresent(String.self, forKey: .publishedAt) {
            return value
        }
        if let value = try container.decodeIfPresent(String.self, forKey: .publishedAtCamel) {
            return value
        }
        if let value = try container.decodeIfPresent(String.self, forKey: .updatedAt) {
            return value
        }
        if let value = try container.decodeIfPresent(String.self, forKey: .updatedAtCamel) {
            return value
        }
        return ""
    }
}

private enum NewsTimelineItem: Identifiable, Hashable {
    case staticNews(StaticNewsItem)
    case channel(ChannelMessage)

    var id: String {
        switch self {
        case .staticNews(let item):
            return "news-\(item.id)"
        case .channel(let message):
            return "channel-\(message.id)"
        }
    }

    var createdAt: String {
        switch self {
        case .staticNews(let item):
            return item.createdAt
        case .channel(let message):
            return message.createdAt
        }
    }
}

private struct NotificationsCenterView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var appearance: VoxiiAppearance

    @State private var notifications: [NotificationItem] = []
    @State private var unreadCount = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    private let refreshTimer = Timer.publish(every: 8, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                VoxiiBackground()

                VStack(spacing: 12) {
                    header
                    content
                }
                .padding(14)
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await loadData(markReadOnOpen: true)
            }
            .onReceive(refreshTimer) { _ in
                guard scenePhase == .active else {
                    return
                }
                Task { await refreshSilently() }
            }
            .alert("Error", isPresented: errorBinding) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(VoxiiTheme.accentGradient)
                    .frame(width: 42, height: 42)
                Image(systemName: "bell.fill")
                    .foregroundStyle(.white)
                    .font(.system(size: 16, weight: .bold))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(VoxiiTheme.text)
                Text(unreadCount > 0 ? "\(unreadCount) unread" : "All caught up")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(VoxiiTheme.muted)
            }

            Spacer()

            Button("Read all") {
                Task { await markAllRead() }
            }
            .buttonStyle(VoxiiGradientButtonStyle(isCompact: true, variant: .neutral))
            .disabled(notifications.isEmpty || unreadCount == 0)

            Button("Clear") {
                Task { await clearAll() }
            }
            .buttonStyle(VoxiiGradientButtonStyle(isCompact: true, variant: .danger))
            .disabled(notifications.isEmpty)
        }
        .voxiiCard(cornerRadius: 18, padding: 14)
    }

    private var content: some View {
        Group {
            if isLoading && notifications.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(VoxiiTheme.accent)
                    Text("Loading notifications...")
                        .foregroundStyle(VoxiiTheme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .voxiiCard(cornerRadius: 18, padding: 18)
            } else if notifications.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(VoxiiTheme.muted)
                    Text("No notifications")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(VoxiiTheme.text)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .voxiiCard(cornerRadius: 18, padding: 18)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(notifications) { item in
                            NotificationRow(
                                item: item,
                                onMarkSourceRead: {
                                    Task { await markSourceRead(item) }
                                },
                                onDelete: {
                                    Task { await delete(item) }
                                }
                            )
                        }
                    }
                }
                .refreshable {
                    await loadData()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )
    }

    private func loadData(markReadOnOpen: Bool = false) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await session.fetchNotifications()
            notifications = sortNotifications(response.notifications)
            unreadCount = max(response.unreadCount, notifications.filter { !$0.read }.count)

            if markReadOnOpen && unreadCount > 0 {
                try await session.markAllNotificationsRead()
                let refreshed = try await session.fetchNotifications()
                notifications = sortNotifications(refreshed.notifications)
                unreadCount = max(refreshed.unreadCount, notifications.filter { !$0.read }.count)
            }

            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func refreshSilently() async {
        guard !isLoading else {
            return
        }

        do {
            let response = try await session.fetchNotifications()
            let sorted = sortNotifications(response.notifications)
            if sorted != notifications {
                notifications = sorted
            }
            unreadCount = max(response.unreadCount, sorted.filter { !$0.read }.count)
        } catch {
            // Ignore background refresh errors.
        }
    }

    private func markAllRead() async {
        do {
            try await session.markAllNotificationsRead()
            await loadData()
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func markSourceRead(_ item: NotificationItem) async {
        guard let fromUserID = item.fromUserId else {
            return
        }

        do {
            try await session.markUserNotificationsRead(fromUserID: fromUserID)
            await loadData()
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func delete(_ item: NotificationItem) async {
        do {
            try await session.deleteNotification(notificationID: item.id)
            notifications.removeAll { $0.id == item.id }
            unreadCount = max(0, notifications.filter { !$0.read }.count)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func clearAll() async {
        do {
            try await session.deleteAllNotifications()
            notifications = []
            unreadCount = 0
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func sortNotifications(_ items: [NotificationItem]) -> [NotificationItem] {
        items.sorted { lhs, rhs in
            let lhsDate = VoxiiDate.date(lhs.createdAt) ?? .distantPast
            let rhsDate = VoxiiDate.date(rhs.createdAt) ?? .distantPast
            if lhsDate == rhsDate {
                return lhs.id > rhs.id
            }
            return lhsDate > rhsDate
        }
    }
}

private struct NotificationRow: View {
    let item: NotificationItem
    let onMarkSourceRead: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(icon)
                .font(.system(size: 20))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(VoxiiTheme.text)

                    if !item.read {
                        Circle()
                            .fill(VoxiiTheme.accent)
                            .frame(width: 7, height: 7)
                    }

                    Spacer(minLength: 8)

                    Text(VoxiiDate.shortDateTime(item.createdAt))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(VoxiiTheme.muted)
                }

                if let bodyText, !bodyText.isEmpty {
                    Text(bodyText)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(VoxiiTheme.muted)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    if !item.read && item.fromUserId != nil {
                        Button("Mark read") {
                            onMarkSourceRead()
                        }
                        .buttonStyle(VoxiiGradientButtonStyle(isCompact: true, variant: .neutral))
                    }

                    Button("Delete") {
                        onDelete()
                    }
                    .buttonStyle(VoxiiGradientButtonStyle(isCompact: true, variant: .danger))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(item.read ? VoxiiTheme.glassSoft : VoxiiTheme.glass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(item.read ? VoxiiTheme.stroke : VoxiiTheme.accent.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.24), radius: 8, x: 0, y: 5)
    }

    private var icon: String {
        switch item.type {
        case "message":
            return "💬"
        case "missed-call":
            return "📞"
        default:
            return "🔔"
        }
    }

    private var title: String {
        switch item.type {
        case "message":
            return item.fromUsername ?? "Unknown"
        case "missed-call":
            return item.fromUsername ?? "Unknown"
        default:
            return item.type.capitalized
        }
    }

    private var bodyText: String? {
        switch item.type {
        case "message":
            return item.content
        case "missed-call":
            let callKind = (item.callType ?? "voice") == "video" ? "video" : "voice"
            return "Missed \(callKind) call"
        default:
            return item.content
        }
    }
}

private struct SettingsHomeView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var appearance: VoxiiAppearance

    @State private var isServerSettingsPresented = false

    var body: some View {
        NavigationStack {
            ZStack {
                VoxiiBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        screenHeader
                        profileCard
                        appearanceSection
                        privacySection
                        serverSection
                        accountSection
                    }
                    .padding(14)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isServerSettingsPresented) {
                ServerSettingsView(initialURL: session.serverURL) { newValue in
                    session.updateServerURL(newValue)
                }
            }
        }
    }

    private var screenHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appearance.t("settings.title"))
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(VoxiiTheme.text)

            Text(appearance.t("settings.subtitle"))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(VoxiiTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: appearance.t("settings.appearance"),
                subtitle: appearance.t("settings.appearanceSubtitle"),
                symbol: "paintpalette.fill"
            )
            appearanceCard
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: appearance.t("settings.privacy"),
                subtitle: appearance.t("settings.privacySubtitle"),
                symbol: "lock.shield.fill"
            )
            privacyCard
        }
    }

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: appearance.t("settings.server"),
                subtitle: appearance.t("settings.serverSubtitle"),
                symbol: "network"
            )
            serverCard
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: appearance.t("settings.account"),
                subtitle: appearance.t("settings.accountSubtitle"),
                symbol: "person.crop.circle.fill"
            )
            actionsCard
        }
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(appearance.t("settings.language"))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(VoxiiTheme.text)

                HStack(spacing: 10) {
                    ForEach(VoxiiLanguage.allCases) { language in
                        Button {
                            appearance.language = language
                        } label: {
                            HStack(spacing: 6) {
                                Text(language.title)
                                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                                if language == appearance.language {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 11, weight: .bold))
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(
                                        language == appearance.language
                                            ? AnyShapeStyle(VoxiiTheme.accentGradient)
                                            : AnyShapeStyle(VoxiiTheme.glass)
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .stroke(VoxiiTheme.stroke, lineWidth: 1)
                            )
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(appearance.t("settings.theme"))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(VoxiiTheme.text)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(VoxiiThemeName.allCases) { theme in
                        Button {
                            appearance.theme = theme
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(themePreview(theme))
                                    .frame(height: 44)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )

                                HStack(spacing: 6) {
                                    Text(appearance.themeLabel(theme))
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(VoxiiTheme.text)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    if theme == appearance.theme {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(VoxiiTheme.accentLight)
                                    }
                                }
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(theme == appearance.theme ? VoxiiTheme.accent.opacity(0.2) : VoxiiTheme.glass)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        theme == appearance.theme ? VoxiiTheme.accent.opacity(0.58) : VoxiiTheme.stroke,
                                        lineWidth: 1
                                    )
                            )
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(appearance.t("settings.accent"))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(VoxiiTheme.text)

                HStack(spacing: 9) {
                    ForEach(appearance.accentPresets, id: \.self) { preset in
                        Button {
                            appearance.setAccent(hex: preset)
                        } label: {
                            Circle()
                                .fill(Color(hex: preset) ?? VoxiiTheme.accent)
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            appearance.accentHex == preset ? Color.white.opacity(0.9) : Color.white.opacity(0.2),
                                            lineWidth: appearance.accentHex == preset ? 2 : 1
                                        )
                                )
                                .overlay {
                                    if appearance.accentHex == preset {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                    }

                    Spacer()

                    ColorPicker(
                        "",
                        selection: Binding(
                            get: { Color(hex: appearance.accentHex) ?? VoxiiTheme.accent },
                            set: { newColor in
                                appearance.setAccent(color: newColor)
                            }
                        ),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(appearance.t("settings.glass"))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(VoxiiTheme.text)
                    Spacer()
                    Text("\(Int(appearance.transparencyPercent))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(VoxiiTheme.muted)
                }

                Slider(value: $appearance.transparencyPercent, in: 50...100, step: 1)
                    .tint(VoxiiTheme.accent)
            }
        }
        .voxiiCard(cornerRadius: 18, padding: 16)
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $appearance.linkPreviewEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(appearance.t("settings.linkPreview"))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(VoxiiTheme.text)
                    Text(appearance.t("settings.linkPreviewDesc"))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(VoxiiTheme.muted)
                }
            }
            .tint(VoxiiTheme.accent)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(VoxiiTheme.glass)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(VoxiiTheme.stroke, lineWidth: 1)
            )

            HStack {
                Text("\(appearance.t("settings.hiddenCount")): \(appearance.hiddenPreviewCount)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(VoxiiTheme.muted)
                Spacer()
                Button(appearance.t("settings.resetHidden")) {
                    appearance.resetHiddenPreviews()
                }
                .buttonStyle(VoxiiGradientButtonStyle(isCompact: true, variant: .neutral))
            }
        }
        .voxiiCard(cornerRadius: 18, padding: 16)
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VoxiiAvatarView(
                    text: session.currentUser?.avatar ?? session.currentUser?.username ?? "V",
                    isOnline: true,
                    size: 54
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.currentUser?.username ?? "Unknown")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(VoxiiTheme.text)
                    Text(session.currentUser?.email ?? "No email")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(VoxiiTheme.muted)
                        .lineLimit(1)
                }

                Spacer()

                Text("Online")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(VoxiiTheme.online)
                    )
            }

            HStack(spacing: 8) {
                settingsBadge(text: "ID: \(session.currentUser?.id ?? 0)", symbol: "number")
                settingsBadge(text: appearance.themeLabel(appearance.theme), symbol: "sparkles")
            }
        }
        .voxiiCard(cornerRadius: 20, padding: 16)
    }

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "network")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(VoxiiTheme.accentLight)

                VStack(alignment: .leading, spacing: 2) {
                    Text(serverHost)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(VoxiiTheme.text)
                    Text(session.serverURL)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(VoxiiTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Spacer()

                Button(appearance.t("settings.changeServer")) {
                    isServerSettingsPresented = true
                }
                .buttonStyle(VoxiiGradientButtonStyle(isCompact: true, variant: .neutral))
            }
            .voxiiCard(cornerRadius: 12, padding: 10)

            Text(appearance.t("settings.serverHint"))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(VoxiiTheme.muted)
        }
        .voxiiCard(cornerRadius: 18, padding: 16)
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appearance.t("settings.signOutHint"))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(VoxiiTheme.muted)

            Button {
                Task { await session.logout() }
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text(session.isBusy ? appearance.t("settings.signingOut") : appearance.t("settings.signOut"))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(VoxiiGradientButtonStyle(variant: .danger))
            .disabled(session.isBusy)
        }
        .voxiiCard(cornerRadius: 18, padding: 16)
    }

    private func sectionHeader(title: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(VoxiiTheme.accentLight)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(VoxiiTheme.accent.opacity(0.2))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(VoxiiTheme.text)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(VoxiiTheme.muted)
            }

            Spacer()
        }
    }

    private func settingsBadge(text: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(VoxiiTheme.text)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(VoxiiTheme.glass)
        )
        .overlay(
            Capsule()
                .stroke(VoxiiTheme.stroke, lineWidth: 1)
        )
    }

    private var serverHost: String {
        guard let host = URL(string: session.serverURL)?.host, !host.isEmpty else {
            return session.serverURL
        }
        return host
    }

    private func themePreview(_ theme: VoxiiThemeName) -> LinearGradient {
        switch theme {
        case .default:
            return LinearGradient(colors: [Color(hex: "#0A0F18") ?? .black, Color(hex: "#0C1322") ?? .black], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .midnight:
            return LinearGradient(colors: [Color(hex: "#0A0A1A") ?? .black, Color(hex: "#121226") ?? .black], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .forest:
            return LinearGradient(colors: [Color(hex: "#0A1A10") ?? .black, Color(hex: "#0F2A1F") ?? .black], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .sunset:
            return LinearGradient(colors: [Color(hex: "#1A0A1A") ?? .black, Color(hex: "#261212") ?? .black], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .ocean:
            return LinearGradient(colors: [Color(hex: "#0A1A26") ?? .black, Color(hex: "#122626") ?? .black], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .coffee:
            return LinearGradient(colors: [Color(hex: "#261C14") ?? .black, Color(hex: "#3C2A1F") ?? .black], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

private enum VoxiiDate {
    private static let isoWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let sqlite: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static let shortDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    static func shortTime(_ value: String) -> String {
        guard let date = parse(value) else {
            return value
        }
        return shortTimeFormatter.string(from: date)
    }

    static func shortDateTime(_ value: String) -> String {
        guard let date = parse(value) else {
            return value
        }
        return shortDateTimeFormatter.string(from: date)
    }

    static func date(_ value: String) -> Date? {
        parse(value)
    }

    private static func parse(_ value: String) -> Date? {
        if let date = isoWithFractional.date(from: value) {
            return date
        }
        if let date = iso.date(from: value) {
            return date
        }
        if let date = sqlite.date(from: value) {
            return date
        }
        if let date = dateOnly.date(from: value) {
            return date
        }
        return nil
    }
}

private struct IncomingCallListenerContainer: UIViewRepresentable {
    let baseServerURL: String
    let token: String
    let onIncomingCall: (IncomingCallPayload) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(baseServerURL: baseServerURL, token: token, onIncomingCall: onIncomingCall)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "voxiiIncomingCall")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false

        webView.loadHTMLString(context.coordinator.buildHTML(), baseURL: context.coordinator.baseURL)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) { }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let baseServerURL: String
        private let token: String
        private let onIncomingCall: (IncomingCallPayload) -> Void
        private(set) var baseURL: URL?

        init(baseServerURL: String, token: String, onIncomingCall: @escaping (IncomingCallPayload) -> Void) {
            self.baseServerURL = baseServerURL
            self.token = token
            self.onIncomingCall = onIncomingCall
            self.baseURL = VoxiiURLBuilder.normalizeBaseURL(baseServerURL)
            super.init()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "voxiiIncomingCall",
                  let payload = message.body as? [String: Any],
                  payload["type"] as? String == "incoming" else {
                return
            }

            let callerSocketId = payload["callerSocketId"] as? String

            let callerId = parseInt(payload["callerId"])
            let callerUsername = payload["callerUsername"] as? String ?? "Unknown"
            let callerAvatar = payload["callerAvatar"] as? String
            let callType = payload["callType"] as? String ?? "video"
            let eventId = payload["eventId"] as? String ?? UUID().uuidString

            DispatchQueue.main.async {
                self.onIncomingCall(
                    IncomingCallPayload(
                        id: eventId,
                        callerId: callerId,
                        callerUsername: callerUsername,
                        callerAvatar: callerAvatar,
                        callerSocketId: callerSocketId,
                        callType: callType
                    )
                )
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { }

        func buildHTML() -> String {
            struct Bootstrap: Encodable {
                let serverURL: String
                let token: String
            }

            let normalizedServer = (baseURL?.absoluteString ?? baseServerURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            let bootstrap = Bootstrap(serverURL: normalizedServer, token: token)
            let data = (try? JSONEncoder().encode(bootstrap)) ?? Data("{}".utf8)
            let json = String(data: data, encoding: .utf8) ?? "{}"
            let socketScriptURL = "\(normalizedServer)/socket.io/socket.io.js"

            return """
            <!doctype html>
            <html>
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover, user-scalable=no">
              <script src="\(socketScriptURL)"></script>
            </head>
            <body>
              <script>
                const cfg = \(json);
                let socket = null;

                function post(type, payload = {}) {
                  if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.voxiiIncomingCall) return;
                  window.webkit.messageHandlers.voxiiIncomingCall.postMessage(Object.assign({ type }, payload));
                }

                function bindHandlers() {
                  if (window.__voxiiIncomingHandlersBound) return;
                  window.__voxiiIncomingHandlersBound = true;

                  socket.on('incoming-call', (data) => {
                    const from = data?.from || {};
                    const callerId = Number.isFinite(from.id) ? from.id : parseInt(from.id || '0', 10) || 0;
                    const callerSocketId = from.socketId || '';
                    if (!callerSocketId) return;
                    const explicitEventId = data?.eventId || data?.event_id || data?.callId || data?.call_id || data?.id || null;

                    post('incoming', {
                      eventId: explicitEventId || `${callerSocketId}-${Date.now()}`,
                      callerId,
                      callerUsername: from.username || 'Unknown',
                      callerAvatar: from.avatar || null,
                      callerSocketId,
                      callType: data?.type || 'video'
                    });
                  });
                }

                async function bootstrap() {
                  if (!cfg.token || typeof io === 'undefined') {
                    return;
                  }

                  socket = io(cfg.serverURL, {
                    auth: { token: cfg.token },
                    transports: ['websocket']
                  });

                  socket.on('connect', () => {
                    bindHandlers();
                  });
                }

                bootstrap();
                window.addEventListener('beforeunload', () => {
                  if (socket) {
                    socket.disconnect();
                  }
                });
              </script>
            </body>
            </html>
            """
        }

        private func parseInt(_ value: Any?) -> Int {
            if let intValue = value as? Int {
                return intValue
            }
            if let doubleValue = value as? Double {
                return Int(doubleValue)
            }
            if let stringValue = value as? String, let intValue = Int(stringValue) {
                return intValue
            }
            return 0
        }
    }
}
