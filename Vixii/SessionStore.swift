import Foundation
import Combine

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var token: String?
    @Published private(set) var currentUser: APIUser?
    @Published var isBusy = false
    @Published var errorMessage: String?

    private let api = VoxiiAPIClient.shared
    private let defaults = UserDefaults.standard

    private let tokenKey = "voxii_token"
    private let currentUserKey = "voxii_current_user"
    private let serverURLKey = "voxii_server_url"
    private let pushSyncMarkerPrefix = "voxii_push_token_sync_marker"
    private let defaultServerURL = "https://voxii.lenuma.ru"
    private let legacyDefaultServerURLs: Set<String> = [
        "http://127.0.0.1:3000",
        "https://144.31.29.216"
    ]
    private var cancellables: Set<AnyCancellable> = []

    init() {
        token = defaults.string(forKey: tokenKey)
        if let userData = defaults.data(forKey: currentUserKey),
           let user = try? JSONDecoder().decode(APIUser.self, from: userData) {
            currentUser = user
        }
        bindPushTokenUpdates()

        if let savedURL = defaults.string(forKey: serverURLKey),
           let normalized = VoxiiURLBuilder.normalizeBaseURL(savedURL)?.absoluteString {
            if legacyDefaultServerURLs.contains(normalized) {
                defaults.set(defaultServerURL, forKey: serverURLKey)
            } else {
                defaults.set(normalized, forKey: serverURLKey)
            }
        } else {
            defaults.set(defaultServerURL, forKey: serverURLKey)
        }

        if isAuthenticated {
            Task {
                await configurePushNotifications()
            }
        }
    }

    var isAuthenticated: Bool {
        token != nil && currentUser != nil
    }

    var serverURL: String {
        guard let saved = defaults.string(forKey: serverURLKey),
              let normalized = VoxiiURLBuilder.normalizeBaseURL(saved)?.absoluteString else {
            return defaultServerURL
        }
        return normalized
    }

    @discardableResult
    func updateServerURL(_ value: String) -> Bool {
        guard let normalized = VoxiiURLBuilder.normalizeBaseURL(value)?.absoluteString else {
            return false
        }
        defaults.set(normalized, forKey: serverURLKey)
        clearPushSyncMarkers()
        if isAuthenticated {
            Task { await syncPushTokenIfNeeded(force: true) }
        }
        return true
    }

    func configurePushNotifications() async {
        await VoxiiPushNotifications.requestAuthorizationAndRegisterIfNeeded()
        await syncPushTokenIfNeeded(force: false)
    }

    func testServerConnection(_ value: String) async throws -> String {
        let candidates = VoxiiURLBuilder.candidateBaseURLs(value)
        guard !candidates.isEmpty else {
            throw APIClientError.invalidServerURL
        }

        var lastError: Error?
        for candidate in candidates {
            do {
                try await api.probeServer(baseURL: candidate.absoluteString)
                return candidate.absoluteString
            } catch {
                lastError = error
            }
        }

        throw lastError ?? APIClientError.invalidServerURL
    }

    // MARK: - Auth

    func login(email: String, password: String) async -> Bool {
        await authenticate(mode: .login(email: email, password: password))
    }

    func register(username: String, email: String, password: String) async -> Bool {
        await authenticate(mode: .register(username: username, email: email, password: password))
    }

    func logout() async {
        guard let token else {
            clearSession()
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            try await api.logout(baseURL: serverURL, token: token)
        } catch {
            // Ignore server failure, local state still needs reset.
        }

        clearSession()
    }

    // MARK: - Users

    func fetchCurrentUserProfile() async throws -> APIUser {
        let token = try requireToken()
        let profile = try await api.fetchCurrentUserProfile(baseURL: serverURL, token: token)
        currentUser = profile
        defaults.set(try? JSONEncoder().encode(profile), forKey: currentUserKey)
        return profile
    }

    func updateCurrentUserProfile(
        username: String? = nil,
        email: String? = nil,
        avatar: String? = nil,
        status: String? = nil
    ) async throws -> APIUser {
        let token = try requireToken()
        let profile = try await api.updateCurrentUserProfile(
            baseURL: serverURL,
            token: token,
            username: username,
            email: email,
            avatar: avatar,
            status: status
        )
        currentUser = profile
        defaults.set(try? JSONEncoder().encode(profile), forKey: currentUserKey)
        return profile
    }

    func fetchUsers() async throws -> [APIUser] {
        let token = try requireToken()
        let users = try await api.fetchUsers(baseURL: serverURL, token: token)
        guard let currentUserID = currentUser?.id else {
            return users
        }
        return users.filter { $0.id != currentUserID }
    }

    func searchUsers(query: String) async throws -> [APIUser] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try await fetchUsers()
        }

        let token = try requireToken()
        let users = try await api.searchUsers(baseURL: serverURL, token: token, query: trimmed)
        guard let currentUserID = currentUser?.id else {
            return users
        }
        return users.filter { $0.id != currentUserID }
    }

    // MARK: - DM

    func fetchMessages(with userID: Int) async throws -> [DirectMessage] {
        let token = try requireToken()
        return try await api.fetchMessages(baseURL: serverURL, token: token, userID: userID)
    }

    func sendMessage(
        to userID: Int,
        text: String,
        fileId: Int? = nil,
        file: APIFileAttachment? = nil,
        replyToId: Int? = nil,
        isVoiceMessage: Bool? = nil
    ) async throws -> DirectMessage {
        let token = try requireToken()
        return try await api.sendMessage(
            baseURL: serverURL,
            token: token,
            to: userID,
            text: text,
            fileId: fileId,
            file: file,
            replyToId: replyToId,
            isVoiceMessage: isVoiceMessage
        )
    }

    func sendVoiceMessageOverSocket(
        to userID: Int,
        text: String,
        file: APIFileAttachment,
        replyToId: Int? = nil,
        isVoiceMessage: Bool = true
    ) async throws -> DirectMessage {
        let token = try requireToken()
        let user = try requireCurrentUser()
        return try await VoxiiSocketDMClient.shared.sendMessage(
            serverURL: serverURL,
            token: token,
            currentUser: user,
            receiverID: userID,
            text: text,
            file: file,
            replyToId: replyToId,
            isVoiceMessage: isVoiceMessage
        )
    }

    func updateMessage(messageID: Int, text: String) async throws -> DirectMessage {
        let token = try requireToken()
        return try await api.updateMessage(baseURL: serverURL, token: token, messageID: messageID, text: text)
    }

    func deleteMessage(messageID: Int) async throws {
        let token = try requireToken()
        try await api.deleteMessage(baseURL: serverURL, token: token, messageID: messageID)
    }

    func addReaction(messageID: Int, emoji: String) async throws -> MessageReactionsResponse {
        let token = try requireToken()
        return try await api.addReaction(baseURL: serverURL, token: token, messageID: messageID, emoji: emoji)
    }

    func removeReaction(messageID: Int, emoji: String) async throws -> MessageReactionsResponse {
        let token = try requireToken()
        return try await api.removeReaction(baseURL: serverURL, token: token, messageID: messageID, emoji: emoji)
    }

    // MARK: - Friends

    func fetchFriends() async throws -> [FriendRequestUser] {
        let token = try requireToken()
        return try await api.fetchFriends(baseURL: serverURL, token: token)
    }

    func fetchPendingFriends() async throws -> [FriendRequestUser] {
        let token = try requireToken()
        return try await api.fetchPendingFriends(baseURL: serverURL, token: token)
    }

    func sendFriendRequest(friendID: Int) async throws {
        let token = try requireToken()
        try await api.sendFriendRequest(baseURL: serverURL, token: token, friendID: friendID)
    }

    func acceptFriendRequest(friendID: Int) async throws {
        let token = try requireToken()
        try await api.acceptFriendRequest(baseURL: serverURL, token: token, friendID: friendID)
    }

    func rejectFriendRequest(friendID: Int) async throws {
        let token = try requireToken()
        try await api.rejectFriendRequest(baseURL: serverURL, token: token, friendID: friendID)
    }

    func removeFriend(friendID: Int) async throws {
        let token = try requireToken()
        try await api.removeFriend(baseURL: serverURL, token: token, friendID: friendID)
    }

    // MARK: - Notifications

    func fetchNotifications() async throws -> NotificationsResponse {
        let token = try requireToken()
        return try await api.fetchNotifications(baseURL: serverURL, token: token)
    }

    func fetchUnreadNotifications() async throws -> NotificationsResponse {
        let token = try requireToken()
        return try await api.fetchUnreadNotifications(baseURL: serverURL, token: token)
    }

    func markAllNotificationsRead() async throws {
        let token = try requireToken()
        try await api.markAllNotificationsRead(baseURL: serverURL, token: token)
    }

    func markUserNotificationsRead(fromUserID: Int) async throws {
        let token = try requireToken()
        try await api.markUserNotificationsRead(baseURL: serverURL, token: token, fromUserID: fromUserID)
    }

    func deleteNotification(notificationID: Int) async throws {
        let token = try requireToken()
        try await api.deleteNotification(baseURL: serverURL, token: token, notificationID: notificationID)
    }

    func deleteAllNotifications() async throws {
        let token = try requireToken()
        try await api.deleteAllNotifications(baseURL: serverURL, token: token)
    }

    // MARK: - Channels

    func fetchChannels() async throws -> [ChannelModel] {
        let token = try requireToken()
        return try await api.fetchChannels(baseURL: serverURL, token: token)
    }

    func fetchSystemChannel() async throws -> ChannelModel {
        let token = try requireToken()
        return try await api.fetchSystemChannel(baseURL: serverURL, token: token)
    }

    func fetchChannelMessages(channelID: Int, limit: Int = 100) async throws -> [ChannelMessage] {
        let token = try requireToken()
        return try await api.fetchChannelMessages(baseURL: serverURL, token: token, channelID: channelID, limit: limit)
    }

    func sendChannelMessage(channelID: Int, content: String, replyToId: Int? = nil) async throws -> ChannelMessage {
        let token = try requireToken()
        return try await api.sendChannelMessage(
            baseURL: serverURL,
            token: token,
            channelID: channelID,
            content: content,
            replyToId: replyToId
        )
    }

    func updateChannelMessage(channelID: Int, messageID: Int, content: String) async throws -> ChannelMessage {
        let token = try requireToken()
        return try await api.updateChannelMessage(
            baseURL: serverURL,
            token: token,
            channelID: channelID,
            messageID: messageID,
            content: content
        )
    }

    func deleteChannelMessage(channelID: Int, messageID: Int) async throws {
        let token = try requireToken()
        try await api.deleteChannelMessage(baseURL: serverURL, token: token, channelID: channelID, messageID: messageID)
    }

    // MARK: - Servers

    func createServer(name: String, description: String? = nil) async throws -> APIServer {
        let token = try requireToken()
        return try await api.createServer(
            baseURL: serverURL,
            token: token,
            name: name,
            description: description
        )
    }

    func fetchServers() async throws -> [APIServer] {
        let token = try requireToken()
        return try await api.fetchServers(baseURL: serverURL, token: token)
    }

    func fetchServerMembers(serverID: Int) async throws -> [APIUser] {
        let token = try requireToken()
        return try await api.fetchServerMembers(baseURL: serverURL, token: token, serverID: serverID)
    }

    // MARK: - Files and transcription

    func uploadFile(
        to receiverID: Int,
        fileData: Data,
        filename: String,
        mimeType: String,
        isVoiceMessage: Bool = false
    ) async throws -> APIFileAttachment {
        let token = try requireToken()
        let senderID = try requireCurrentUser().id
        return try await api.uploadFile(
            baseURL: serverURL,
            token: token,
            fileData: fileData,
            filename: filename,
            mimeType: mimeType,
            receiverID: receiverID,
            senderID: senderID,
            isVoiceMessage: isVoiceMessage
        )
    }

    func transcribeAudio(fileData: Data, filename: String, mimeType: String) async throws -> TranscriptionResult {
        let token = try requireToken()
        return try await api.transcribeAudio(
            baseURL: serverURL,
            token: token,
            audioData: fileData,
            filename: filename,
            mimeType: mimeType
        )
    }

    // MARK: - Utilities

    func fetchLinkPreview(url: String) async throws -> LinkPreviewMetadata {
        try await api.fetchLinkPreview(baseURL: serverURL, url: url)
    }

    func absoluteURL(for pathOrURL: String) -> URL? {
        if let absolute = URL(string: pathOrURL), absolute.scheme != nil {
            return absolute
        }

        guard let base = VoxiiURLBuilder.normalizeBaseURL(serverURL) else {
            return nil
        }

        let cleaned = pathOrURL.hasPrefix("/") ? String(pathOrURL.dropFirst()) : pathOrURL
        return base.appending(path: cleaned)
    }

    private enum AuthMode {
        case login(email: String, password: String)
        case register(username: String, email: String, password: String)
    }

    private func authenticate(mode: AuthMode) async -> Bool {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            let response: AuthResponse
            switch mode {
            case let .login(email, password):
                response = try await api.login(baseURL: serverURL, email: email, password: password)
            case let .register(username, email, password):
                response = try await api.register(baseURL: serverURL, username: username, email: email, password: password)
            }

            saveSession(token: response.token, user: response.user)
            await configurePushNotifications()
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    private func requireToken() throws -> String {
        guard let token else {
            throw APIClientError.server("Not authenticated.")
        }
        return token
    }

    private func requireCurrentUser() throws -> APIUser {
        guard let currentUser else {
            throw APIClientError.server("Not authenticated.")
        }
        return currentUser
    }

    private func saveSession(token: String, user: APIUser) {
        self.token = token
        currentUser = user
        defaults.set(token, forKey: tokenKey)
        defaults.set(try? JSONEncoder().encode(user), forKey: currentUserKey)
    }

    private func clearSession() {
        token = nil
        currentUser = nil
        errorMessage = nil
        clearPushSyncMarkers()
        defaults.removeObject(forKey: tokenKey)
        defaults.removeObject(forKey: currentUserKey)
    }

    private func bindPushTokenUpdates() {
        NotificationCenter.default.publisher(for: .voxiiPushTokenDidUpdate)
            .sink { [weak self] notification in
                guard let self else {
                    return
                }
                let provider = (notification.object as? [String: String])?["provider"] ?? "apns"
                self.defaults.removeObject(forKey: self.pushSyncMarkerKey(for: provider))
                Task { await self.syncPushTokenIfNeeded(force: true) }
            }
            .store(in: &cancellables)
    }

    private func syncPushTokenIfNeeded(force: Bool) async {
        guard let sessionToken = token,
              let user = currentUser else {
            return
        }

        if let apnsToken = VoxiiPushNotifications.storedAPNSToken {
            await syncSinglePushToken(
                provider: "apns",
                deviceToken: apnsToken,
                sessionToken: sessionToken,
                userID: user.id,
                force: force
            )
        }

        if let voipToken = VoxiiPushNotifications.storedVoIPToken {
            await syncSinglePushToken(
                provider: "voip",
                deviceToken: voipToken,
                sessionToken: sessionToken,
                userID: user.id,
                force: force
            )
        }
    }

    private func syncSinglePushToken(
        provider: String,
        deviceToken: String,
        sessionToken: String,
        userID: Int,
        force: Bool
    ) async {
        let marker = "\(serverURL)|\(userID)|\(provider)|\(deviceToken)"
        let key = pushSyncMarkerKey(for: provider)
        if !force, defaults.string(forKey: key) == marker {
            return
        }

        do {
            try await api.registerPushToken(
                baseURL: serverURL,
                token: sessionToken,
                deviceToken: deviceToken,
                provider: provider
            )
            defaults.set(marker, forKey: key)
        } catch {
            print("[SessionStore][Push] \(provider) token sync failed: \(error.localizedDescription)")
        }
    }

    private func clearPushSyncMarkers() {
        defaults.removeObject(forKey: pushSyncMarkerKey(for: "apns"))
        defaults.removeObject(forKey: pushSyncMarkerKey(for: "voip"))
    }

    private func pushSyncMarkerKey(for provider: String) -> String {
        "\(pushSyncMarkerPrefix)_\(provider)"
    }
}
