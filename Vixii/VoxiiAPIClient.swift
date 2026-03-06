import Foundation
import UniformTypeIdentifiers

enum APIClientError: LocalizedError {
    case invalidServerURL
    case badResponse
    case server(String)
    case invalidUploadData

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Invalid server URL."
        case .badResponse:
            return "Unexpected server response."
        case .server(let message):
            return message
        case .invalidUploadData:
            return "Invalid file data for upload."
        }
    }
}

final class VoxiiAPIClient {
    static let shared = VoxiiAPIClient()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let secureSession: URLSession

    private init(session: URLSession = .shared) {
        self.secureSession = session
    }

    // MARK: - Auth

    func login(baseURL: String, email: String, password: String) async throws -> AuthResponse {
        let payload = ["email": email, "password": password]
        return try await request(baseURL: baseURL, path: "/api/login", method: "POST", body: payload)
    }

    func register(baseURL: String, username: String, email: String, password: String) async throws -> AuthResponse {
        let payload = ["username": username, "email": email, "password": password]
        return try await request(baseURL: baseURL, path: "/api/register", method: "POST", body: payload)
    }

    func logout(baseURL: String, token: String) async throws {
        _ = try await request(
            baseURL: baseURL,
            path: "/api/logout",
            method: "POST",
            token: token,
            body: [String: String]()
        ) as EmptyResponse
    }

    // MARK: - Connectivity

    func probeServer(baseURL: String) async throws {
        guard let url = VoxiiURLBuilder.endpoint(baseURL: baseURL, path: "/api/login") else {
            throw APIClientError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = #"{"email":"","password":""}"#.data(using: .utf8)

        do {
            let (_, response) = try await data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIClientError.badResponse
            }

            switch http.statusCode {
            case 200...299, 400, 401, 403, 405, 409, 415, 422, 429:
                return
            case 404:
                throw APIClientError.server("Server reachable, but Voxii API endpoint /api/* was not found.")
            case 500...599:
                throw APIClientError.server("Server is reachable, but backend returned \(http.statusCode).")
            default:
                throw APIClientError.server("Server reachable, but returned unexpected status \(http.statusCode).")
            }
        } catch {
            if let mapped = mapTransportError(error) {
                throw mapped
            }
            throw error
        }
    }

    // MARK: - Users & DM

    func fetchCurrentUserProfile(baseURL: String, token: String) async throws -> APIUser {
        try await request(baseURL: baseURL, path: "/api/user/profile", method: "GET", token: token)
    }

    func updateCurrentUserProfile(
        baseURL: String,
        token: String,
        username: String? = nil,
        email: String? = nil,
        avatar: String? = nil,
        status: String? = nil
    ) async throws -> APIUser {
        try await request(
            baseURL: baseURL,
            path: "/api/user/profile",
            method: "PUT",
            token: token,
            body: UpdateUserProfileRequest(
                username: username,
                email: email,
                avatar: avatar,
                status: status
            )
        )
    }

    func fetchUsers(baseURL: String, token: String) async throws -> [APIUser] {
        try await request(baseURL: baseURL, path: "/api/users", method: "GET", token: token)
    }

    func searchUsers(baseURL: String, token: String, query: String) async throws -> [APIUser] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return try await request(
            baseURL: baseURL,
            path: "/api/users/search?q=\(encodedQuery)",
            method: "GET",
            token: token
        )
    }

    func fetchMessages(baseURL: String, token: String, userID: Int) async throws -> [DirectMessage] {
        try await request(baseURL: baseURL, path: "/api/dm/\(userID)", method: "GET", token: token)
    }

    func sendMessage(
        baseURL: String,
        token: String,
        to receiverID: Int,
        text: String,
        fileId: Int? = nil,
        file: APIFileAttachment? = nil,
        replyToId: Int? = nil,
        isVoiceMessage: Bool? = nil
    ) async throws -> DirectMessage {
        let payload = SendMessageRequest(
            text: text,
            content: text,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            receiverId: receiverID,
            fileId: fileId,
            file: file.map(SendMessageFilePayload.init),
            replyToId: replyToId,
            isVoiceMessage: isVoiceMessage
        )
        return try await request(
            baseURL: baseURL,
            path: "/api/dm/\(receiverID)",
            method: "POST",
            token: token,
            body: payload
        )
    }

    func updateMessage(baseURL: String, token: String, messageID: Int, text: String) async throws -> DirectMessage {
        try await request(
            baseURL: baseURL,
            path: "/api/dm/\(messageID)",
            method: "PUT",
            token: token,
            body: UpdateMessageRequest(text: text)
        )
    }

    func deleteMessage(baseURL: String, token: String, messageID: Int) async throws {
        _ = try await request(
            baseURL: baseURL,
            path: "/api/dm/\(messageID)",
            method: "DELETE",
            token: token
        ) as EmptyResponse
    }

    func addReaction(baseURL: String, token: String, messageID: Int, emoji: String) async throws -> MessageReactionsResponse {
        let payload = ReactionRequest(emoji: emoji)
        do {
            return try await request(
                baseURL: baseURL,
                path: "/api/dm/\(messageID)/reaction",
                method: "POST",
                token: token,
                body: payload
            )
        } catch {
            guard shouldFallbackToLegacyReactionsEndpoint(after: error) else {
                throw error
            }
            return try await request(
                baseURL: baseURL,
                path: "/api/dm/\(messageID)/reactions",
                method: "POST",
                token: token,
                body: payload
            )
        }
    }

    func removeReaction(baseURL: String, token: String, messageID: Int, emoji: String) async throws -> MessageReactionsResponse {
        let encodedEmoji = encodePathComponent(emoji)
        do {
            return try await request(
                baseURL: baseURL,
                path: "/api/dm/\(messageID)/reaction/\(encodedEmoji)",
                method: "DELETE",
                token: token
            )
        } catch {
            guard shouldFallbackToLegacyReactionsEndpoint(after: error) else {
                throw error
            }
            return try await request(
                baseURL: baseURL,
                path: "/api/dm/\(messageID)/reactions",
                method: "DELETE",
                token: token,
                body: ReactionRequest(emoji: emoji)
            )
        }
    }

    // MARK: - Channels

    func fetchChannels(baseURL: String, token: String) async throws -> [ChannelModel] {
        try await request(baseURL: baseURL, path: "/api/channels", method: "GET", token: token)
    }

    func fetchSystemChannel(baseURL: String, token: String) async throws -> ChannelModel {
        let data = try await requestData(
            baseURL: baseURL,
            path: "/api/channels/system",
            method: "GET",
            token: token
        )
        if let channel = decodeSystemChannel(from: data) {
            return channel
        }
        throw APIClientError.server("Unexpected system channel response format: \(responsePreview(data))")
    }

    func fetchChannelMessages(baseURL: String, token: String, channelID: Int, limit: Int = 100) async throws -> [ChannelMessage] {
        let data = try await requestData(
            baseURL: baseURL,
            path: "/api/channels/\(channelID)/messages?limit=\(limit)",
            method: "GET",
            token: token
        )
        if let messages = decodeChannelMessages(from: data) {
            return messages
        }
        throw APIClientError.server("Unexpected channel messages response format: \(responsePreview(data))")
    }

    func sendChannelMessage(baseURL: String, token: String, channelID: Int, content: String, replyToId: Int? = nil) async throws -> ChannelMessage {
        try await request(
            baseURL: baseURL,
            path: "/api/channels/\(channelID)/messages",
            method: "POST",
            token: token,
            body: ChannelMessageRequest(content: content, replyToId: replyToId)
        )
    }

    func updateChannelMessage(baseURL: String, token: String, channelID: Int, messageID: Int, content: String) async throws -> ChannelMessage {
        try await request(
            baseURL: baseURL,
            path: "/api/channels/\(channelID)/messages/\(messageID)",
            method: "PUT",
            token: token,
            body: ChannelMessageRequest(content: content, replyToId: nil)
        )
    }

    func deleteChannelMessage(baseURL: String, token: String, channelID: Int, messageID: Int) async throws {
        _ = try await request(
            baseURL: baseURL,
            path: "/api/channels/\(channelID)/messages/\(messageID)",
            method: "DELETE",
            token: token
        ) as EmptyResponse
    }

    // MARK: - Servers

    func createServer(baseURL: String, token: String, name: String, description: String? = nil) async throws -> APIServer {
        try await request(
            baseURL: baseURL,
            path: "/api/servers",
            method: "POST",
            token: token,
            body: CreateServerRequest(name: name, description: description)
        )
    }

    func fetchServers(baseURL: String, token: String) async throws -> [APIServer] {
        try await request(baseURL: baseURL, path: "/api/servers", method: "GET", token: token)
    }

    func fetchServerMembers(baseURL: String, token: String, serverID: Int) async throws -> [APIUser] {
        try await request(
            baseURL: baseURL,
            path: "/api/servers/\(serverID)/members",
            method: "GET",
            token: token
        )
    }

    // MARK: - Friends

    func fetchFriends(baseURL: String, token: String) async throws -> [FriendRequestUser] {
        try await request(baseURL: baseURL, path: "/api/friends", method: "GET", token: token)
    }

    func fetchPendingFriends(baseURL: String, token: String) async throws -> [FriendRequestUser] {
        try await request(baseURL: baseURL, path: "/api/friends/pending", method: "GET", token: token)
    }

    func sendFriendRequest(baseURL: String, token: String, friendID: Int) async throws {
        _ = try await request(
            baseURL: baseURL,
            path: "/api/friends/request",
            method: "POST",
            token: token,
            body: FriendActionRequest(friendId: friendID)
        ) as EmptyResponse
    }

    func acceptFriendRequest(baseURL: String, token: String, friendID: Int) async throws {
        _ = try await request(
            baseURL: baseURL,
            path: "/api/friends/accept",
            method: "POST",
            token: token,
            body: FriendActionRequest(friendId: friendID)
        ) as EmptyResponse
    }

    func rejectFriendRequest(baseURL: String, token: String, friendID: Int) async throws {
        _ = try await request(
            baseURL: baseURL,
            path: "/api/friends/reject",
            method: "POST",
            token: token,
            body: FriendActionRequest(friendId: friendID)
        ) as EmptyResponse
    }

    func removeFriend(baseURL: String, token: String, friendID: Int) async throws {
        _ = try await request(
            baseURL: baseURL,
            path: "/api/friends/\(friendID)",
            method: "DELETE",
            token: token
        ) as EmptyResponse
    }

    // MARK: - Notifications

    func fetchNotifications(baseURL: String, token: String) async throws -> NotificationsResponse {
        let data = try await requestData(
            baseURL: baseURL,
            path: "/api/notifications",
            method: "GET",
            token: token
        )
        if let decoded = decodeNotificationsResponse(from: data) {
            return decoded
        }
        throw APIClientError.server("Unexpected notifications response format: \(responsePreview(data))")
    }

    func fetchUnreadNotifications(baseURL: String, token: String) async throws -> NotificationsResponse {
        let data = try await requestData(
            baseURL: baseURL,
            path: "/api/notifications/unread",
            method: "GET",
            token: token
        )
        if let decoded = decodeNotificationsResponse(from: data) {
            return decoded
        }
        throw APIClientError.server("Unexpected unread notifications response format: \(responsePreview(data))")
    }

    func markAllNotificationsRead(baseURL: String, token: String) async throws {
        _ = try await request(
            baseURL: baseURL,
            path: "/api/notifications/mark-all-read",
            method: "POST",
            token: token,
            body: [String: String]()
        ) as EmptyResponse
    }

    func markUserNotificationsRead(baseURL: String, token: String, fromUserID: Int) async throws {
        _ = try await request(
            baseURL: baseURL,
            path: "/api/notifications/mark-user-read",
            method: "POST",
            token: token,
            body: MarkUserReadRequest(fromUserId: fromUserID)
        ) as EmptyResponse
    }

    func deleteNotification(baseURL: String, token: String, notificationID: Int) async throws {
        _ = try await request(
            baseURL: baseURL,
            path: "/api/notifications/\(notificationID)",
            method: "DELETE",
            token: token
        ) as EmptyResponse
    }

    func deleteAllNotifications(baseURL: String, token: String) async throws {
        _ = try await request(baseURL: baseURL, path: "/api/notifications", method: "DELETE", token: token) as EmptyResponse
    }

    func registerPushToken(
        baseURL: String,
        token: String,
        deviceToken: String,
        provider: String = "apns"
    ) async throws {
        let payload = PushTokenRegistrationRequest(deviceToken: deviceToken, provider: provider)
        let candidatePaths = [
            "/api/push/register",
            "/api/notifications/push-token",
            "/api/device-token",
            "/api/device/register"
        ]

        var lastError: Error?
        for path in candidatePaths {
            do {
                _ = try await request(
                    baseURL: baseURL,
                    path: path,
                    method: "POST",
                    token: token,
                    body: payload
                ) as EmptyResponse
                return
            } catch {
                if shouldFallbackToAlternativePushEndpoint(after: error) {
                    lastError = error
                    continue
                }
                throw error
            }
        }

        if let lastError {
            throw lastError
        }
    }

    // MARK: - Link preview

    func fetchLinkPreview(baseURL: String, url: String) async throws -> LinkPreviewMetadata {
        let encoded = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return try await request(
            baseURL: baseURL,
            path: "/api/link-preview?url=\(encoded)",
            method: "GET"
        )
    }

    // MARK: - Upload / Transcribe

    func uploadFile(
        baseURL: String,
        token: String,
        fileData: Data,
        filename: String,
        mimeType: String,
        receiverID: Int,
        senderID: Int,
        isVoiceMessage: Bool = false
    ) async throws -> APIFileAttachment {
        guard !fileData.isEmpty else {
            throw APIClientError.invalidUploadData
        }

        var fields = [
            "dmId": String(receiverID),
            "dm_id": String(receiverID),
            "senderId": String(senderID),
            "sender_id": String(senderID),
            "receiverId": String(receiverID),
            "receiver_id": String(receiverID)
        ]
        if isVoiceMessage {
            fields["isVoiceMessage"] = "true"
            fields["is_voice_message"] = "true"
            fields["voiceMessage"] = "true"
            fields["voice_message"] = "true"
            fields["type"] = "voice"
            fields["messageType"] = "voice"
            fields["folder"] = "voice_messages"
        }

        return try await uploadMultipart(
            baseURL: baseURL,
            token: token,
            path: "/api/upload",
            fieldName: "file",
            filename: filename,
            mimeType: mimeType,
            fileData: fileData,
            additionalFields: fields,
            responseType: APIFileAttachment.self
        )
    }

    func transcribeAudio(
        baseURL: String,
        token: String,
        audioData: Data,
        filename: String = "voice-message.webm",
        mimeType: String = "audio/webm"
    ) async throws -> TranscriptionResult {
        guard !audioData.isEmpty else {
            throw APIClientError.invalidUploadData
        }

        return try await uploadMultipart(
            baseURL: baseURL,
            token: token,
            path: "/api/transcribe",
            fieldName: "file",
            filename: filename,
            mimeType: mimeType,
            fileData: audioData,
            additionalFields: [:],
            responseType: TranscriptionResult.self
        )
    }

    // MARK: - Base JSON requests

    private func request<T: Decodable>(
        baseURL: String,
        path: String,
        method: String,
        token: String? = nil
    ) async throws -> T {
        try await performRequest(
            baseURL: baseURL,
            path: path,
            method: method,
            token: token,
            bodyData: nil
        )
    }

    private func request<T: Decodable, B: Encodable>(
        baseURL: String,
        path: String,
        method: String,
        token: String? = nil,
        body: B
    ) async throws -> T {
        let bodyData = try encoder.encode(body)
        return try await performRequest(
            baseURL: baseURL,
            path: path,
            method: method,
            token: token,
            bodyData: bodyData
        )
    }

    private func performRequest<T: Decodable>(
        baseURL: String,
        path: String,
        method: String,
        token: String?,
        bodyData: Data?
    ) async throws -> T {
        let data = try await requestData(
            baseURL: baseURL,
            path: path,
            method: method,
            token: token,
            bodyData: bodyData
        )
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            if T.self == EmptyResponse.self {
                return EmptyResponse() as! T
            }
            throw error
        }
    }

    // MARK: - Multipart

    private func uploadMultipart<T: Decodable>(
        baseURL: String,
        token: String,
        path: String,
        fieldName: String,
        filename: String,
        mimeType: String,
        fileData: Data,
        additionalFields: [String: String],
        responseType: T.Type
    ) async throws -> T {
        guard let url = VoxiiURLBuilder.endpoint(baseURL: baseURL, path: path) else {
            throw APIClientError.invalidServerURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = makeMultipartBody(
            boundary: boundary,
            fieldName: fieldName,
            filename: filename,
            mimeType: mimeType,
            fileData: fileData,
            fields: additionalFields
        )

        let (data, response) = try await data(for: request)
        return try parseResponse(data: data, response: response)
    }

    private func makeMultipartBody(
        boundary: String,
        fieldName: String,
        filename: String,
        mimeType: String,
        fileData: Data,
        fields: [String: String]
    ) -> Data {
        let lineBreak = "\r\n"
        var body = Data()

        fields.forEach { key, value in
            body.appendString("--\(boundary)\(lineBreak)")
            body.appendString("Content-Disposition: form-data; name=\"\(key)\"\(lineBreak)\(lineBreak)")
            body.appendString("\(value)\(lineBreak)")
        }

        body.appendString("--\(boundary)\(lineBreak)")
        body.appendString("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\(lineBreak)")
        body.appendString("Content-Type: \(mimeType)\(lineBreak)\(lineBreak)")
        body.append(fileData)
        body.appendString(lineBreak)
        body.appendString("--\(boundary)--\(lineBreak)")

        return body
    }

    private func shouldFallbackToLegacyReactionsEndpoint(after error: Error) -> Bool {
        guard case let APIClientError.server(message) = error else {
            return false
        }
        return message.contains("404") || message.contains("405")
    }

    private func shouldFallbackToAlternativePushEndpoint(after error: Error) -> Bool {
        guard case let APIClientError.server(message) = error else {
            return false
        }
        let lowercased = message.lowercased()
        return lowercased.contains("404")
            || lowercased.contains("405")
            || lowercased.contains("cannot post")
            || lowercased.contains("not found")
            || lowercased.contains("no route")
    }

    private func shouldRetryRequest(after error: Error, method: String) -> Bool {
        guard method.uppercased() == "GET" else {
            return false
        }

        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return false
        }

        let code = URLError.Code(rawValue: nsError.code)
        return code == .timedOut || code == .networkConnectionLost
    }

    private func encodePathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private func requestData(
        baseURL: String,
        path: String,
        method: String,
        token: String?,
        bodyData: Data? = nil
    ) async throws -> Data {
        guard let url = VoxiiURLBuilder.endpoint(baseURL: baseURL, path: path) else {
            throw APIClientError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = bodyData

        do {
            let (data, response) = try await data(for: request)
            return try parseRawResponseData(data: data, response: response)
        } catch {
            if shouldRetryRequest(after: error, method: method) {
                var retryRequest = request
                retryRequest.timeoutInterval = max(request.timeoutInterval, 45)
                do {
                    let (data, response) = try await data(for: retryRequest)
                    return try parseRawResponseData(data: data, response: response)
                } catch {
                    if let mapped = mapTransportError(error) {
                        throw mapped
                    }
                    throw error
                }
            }
            if let mapped = mapTransportError(error) {
                throw mapped
            }
            throw error
        }
    }

    private func parseRawResponseData(data: Data, response: URLResponse) throws -> Data {
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.badResponse
        }
        guard (200...299).contains(http.statusCode) else {
            if let apiError = try? decoder.decode(APIErrorResponse.self, from: data) {
                throw APIClientError.server(apiError.error)
            }
            if let rawText = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !rawText.isEmpty {
                throw APIClientError.server(rawText)
            }
            throw APIClientError.server("Server returned status \(http.statusCode).")
        }
        return data
    }

    private func decodeSystemChannel(from data: Data) -> ChannelModel? {
        if let channel = try? decoder.decode(ChannelModel.self, from: data) {
            return channel
        }
        if let envelope = try? decoder.decode(SystemChannelEnvelope.self, from: data) {
            return envelope.channel
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        return decodeSystemChannelCandidate(from: json)
    }

    private func decodeChannelMessages(from data: Data) -> [ChannelMessage]? {
        if let messages = try? decoder.decode([ChannelMessage].self, from: data) {
            return messages
        }
        if let envelope = try? decoder.decode(ChannelMessagesEnvelope.self, from: data) {
            return envelope.messages
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        guard let rawItems = extractChannelMessagesArray(from: json) else {
            if let single = decodeSingleChannelMessage(from: json) {
                return [single]
            }
            return nil
        }

        let decoded = decodeChannelMessagesArray(rawItems)
        if !decoded.isEmpty || rawItems.isEmpty {
            return decoded
        }

        return nil
    }

    private func decodeSystemChannelCandidate(from value: Any) -> ChannelModel? {
        if let object = value as? [String: Any] {
            let normalizedKeys = Set(object.keys.map { $0.lowercased() })
            let channelLikeKeys: Set<String> = [
                "id",
                "name",
                "type",
                "description",
                "is_system",
                "issystem",
                "owner_id",
                "ownerid",
                "subscribercount",
                "subscriber_count"
            ]

            if !channelLikeKeys.isDisjoint(with: normalizedKeys),
               let objectData = try? JSONSerialization.data(withJSONObject: object),
               let decoded = try? decoder.decode(ChannelModel.self, from: objectData) {
                return decoded
            }

            let priorityNestedCandidates: [Any?] = [
                object["channel"],
                object["systemChannel"],
                object["system_channel"],
                object["data"],
                object["result"],
                object["payload"],
                object["item"]
            ]

            for candidate in priorityNestedCandidates {
                guard let candidate else {
                    continue
                }
                if let decoded = decodeSystemChannelCandidate(from: candidate) {
                    return decoded
                }
            }

            for nested in object.values {
                if let decoded = decodeSystemChannelCandidate(from: nested) {
                    return decoded
                }
            }

            return nil
        }

        if let array = value as? [Any] {
            for item in array {
                if let decoded = decodeSystemChannelCandidate(from: item) {
                    return decoded
                }
            }
            return nil
        }

        if let jsonString = value as? String,
           let jsonData = jsonString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) {
            return decodeSystemChannelCandidate(from: json)
        }

        return nil
    }

    private func extractChannelMessagesArray(from value: Any) -> [Any]? {
        if let array = value as? [Any] {
            return array
        }

        guard let object = value as? [String: Any] else {
            if let jsonString = value as? String,
               let jsonData = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) {
                return extractChannelMessagesArray(from: json)
            }
            return nil
        }

        let priorityKeys = [
            "messages",
            "items",
            "results",
            "history",
            "channelMessages",
            "channel_messages",
            "list",
            "data",
            "payload",
            "result"
        ]

        for key in priorityKeys {
            if let nested = object[key],
               let array = extractChannelMessagesArray(from: nested) {
                return array
            }
        }

        for nested in object.values {
            if let array = extractChannelMessagesArray(from: nested) {
                return array
            }
        }

        return nil
    }

    private func decodeChannelMessagesArray(_ rawItems: [Any]) -> [ChannelMessage] {
        rawItems.compactMap { item in
            decodeSingleChannelMessage(from: item)
        }
    }

    private func decodeSingleChannelMessage(from value: Any) -> ChannelMessage? {
        if let object = value as? [String: Any] {
            if let nested = object["message"] {
                return decodeSingleChannelMessage(from: nested)
            }
            if let nested = object["data"] as? [String: Any],
               let decoded = decodeSingleChannelMessage(from: nested) {
                return decoded
            }

            let normalizedKeys = Set(object.keys.map { $0.lowercased() })
            let messageLikeKeys: Set<String> = [
                "id",
                "content",
                "text",
                "channel_id",
                "channelid",
                "sender_id",
                "senderid",
                "created_at",
                "createdat",
                "timestamp"
            ]
            guard !messageLikeKeys.isDisjoint(with: normalizedKeys),
                  let itemData = try? JSONSerialization.data(withJSONObject: object) else {
                return nil
            }
            return try? decoder.decode(ChannelMessage.self, from: itemData)
        }

        if let jsonString = value as? String,
           let jsonData = jsonString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) {
            return decodeSingleChannelMessage(from: json)
        }

        return nil
    }

    private func decodeNotificationsResponse(from data: Data) -> NotificationsResponse? {
        if let response = try? decoder.decode(NotificationsResponse.self, from: data) {
            return response
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        if let array = json as? [Any] {
            let items = decodeNotificationsArray(array)
            if !items.isEmpty {
                let unread = items.filter { !$0.read }.count
                return NotificationsResponse(notifications: items, unreadCount: unread)
            }
            return array.isEmpty ? NotificationsResponse(notifications: [], unreadCount: 0) : nil
        }

        guard let object = json as? [String: Any] else {
            return nil
        }

        let unreadCount =
            decodeInt(from: object["unreadCount"])
            ?? decodeInt(from: object["unread_count"])
            ?? decodeInt(from: object["unread"])
            ?? 0

        let candidateArrays: [[Any]] = [
            decodeJSONArray(from: object["notifications"]),
            decodeJSONArray(from: object["items"]),
            decodeJSONArray(from: object["results"]),
            decodeJSONArray(from: object["data"]),
            decodeJSONArray(from: (object["data"] as? [String: Any])?["notifications"]),
            decodeJSONArray(from: (object["data"] as? [String: Any])?["items"]),
            decodeJSONArray(from: (object["payload"] as? [String: Any])?["notifications"])
        ].compactMap { $0 }

        for rawArray in candidateArrays {
            let decodedItems = decodeNotificationsArray(rawArray)
            if !decodedItems.isEmpty || rawArray.isEmpty {
                let inferredUnread = decodedItems.filter { !$0.read }.count
                return NotificationsResponse(
                    notifications: decodedItems,
                    unreadCount: max(unreadCount, inferredUnread)
                )
            }
        }

        if let decoded = decodeNotificationObject(object) {
            let inferredUnread = decoded.read ? 0 : 1
            return NotificationsResponse(
                notifications: [decoded],
                unreadCount: max(unreadCount, inferredUnread)
            )
        }

        return nil
    }

    private func decodeNotificationsArray(_ array: [Any]) -> [NotificationItem] {
        array.compactMap { item in
            if let object = item as? [String: Any] {
                if let decoded = decodeNotificationObject(object) {
                    return decoded
                }
                if let nested = object["notification"] as? [String: Any],
                   let decoded = decodeNotificationObject(nested) {
                    return decoded
                }
                if let nested = object["data"] as? [String: Any],
                   let decoded = decodeNotificationObject(nested) {
                    return decoded
                }
            }
            if let jsonString = item as? String,
               let jsonData = jsonString.data(using: .utf8),
               let decoded = try? decoder.decode(NotificationItem.self, from: jsonData) {
                return decoded
            }
            return nil
        }
    }

    private func decodeNotificationObject(_ object: [String: Any]) -> NotificationItem? {
        guard let itemData = try? JSONSerialization.data(withJSONObject: object) else {
            return nil
        }
        return try? decoder.decode(NotificationItem.self, from: itemData)
    }

    private func decodeJSONArray(from value: Any?) -> [Any]? {
        if let array = value as? [Any] {
            return array
        }
        if let object = value as? [String: Any] {
            if let nested = object["notifications"] as? [Any] {
                return nested
            }
            if let nested = object["items"] as? [Any] {
                return nested
            }
            if let nested = object["results"] as? [Any] {
                return nested
            }
            let values = Array(object.values)
            if !values.isEmpty && values.allSatisfy({ $0 is [String: Any] }) {
                return values
            }
        }
        return nil
    }

    private func decodeInt(from value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let doubleValue = value as? Double {
            return Int(doubleValue)
        }
        if let boolValue = value as? Bool {
            return boolValue ? 1 : 0
        }
        if let stringValue = value as? String {
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let intValue = Int(trimmed) {
                return intValue
            }
            if let doubleValue = Double(trimmed) {
                return Int(doubleValue)
            }
        }
        return nil
    }

    private func responsePreview(_ data: Data, limit: Int = 240) -> String {
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return "<empty>"
        }
        if text.count <= limit {
            return text
        }
        let end = text.index(text.startIndex, offsetBy: limit)
        return "\(text[..<end])…"
    }

    private func mapTransportError(_ error: Error) -> APIClientError? {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return nil
        }

        let code = URLError.Code(rawValue: nsError.code)
        switch code {
        case .timedOut:
            return .server("Connection timeout. Check server address and availability.")
        case .cannotFindHost, .dnsLookupFailed:
            return .server("Cannot resolve host. Verify domain or IP address.")
        case .cannotConnectToHost, .networkConnectionLost:
            return .server("Cannot connect to server. Verify port, firewall and reverse proxy settings.")
        case .notConnectedToInternet:
            return .server("No internet connection.")
        case .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .clientCertificateRequired:
            return .server("TLS/SSL handshake failed. Check HTTPS certificate chain on the server.")
        case .appTransportSecurityRequiresSecureConnection:
            return .server("Server requires HTTPS. Use https:// in server URL.")
        default:
            return .server("Network request failed (\(nsError.code)): \(nsError.localizedDescription)")
        }
    }

    private func parseResponse<T: Decodable>(data: Data, response: URLResponse) throws -> T {
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.badResponse
        }

        guard (200...299).contains(http.statusCode) else {
            if let apiError = try? decoder.decode(APIErrorResponse.self, from: data) {
                throw APIClientError.server(apiError.error)
            }
            if let rawText = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !rawText.isEmpty {
                throw APIClientError.server(rawText)
            }
            throw APIClientError.server("Server returned status \(http.statusCode).")
        }

        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }

        return try decoder.decode(T.self, from: data)
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await secureSession.data(for: request)
    }
}

private struct SystemChannelEnvelope: Decodable {
    let channel: ChannelModel
}

private struct ChannelMessagesEnvelope: Decodable {
    let messages: [ChannelMessage]
}

private struct PushTokenRegistrationRequest: Encodable {
    let token: String
    let deviceToken: String
    let apnsToken: String
    let platform: String
    let provider: String
    let bundleId: String
    let appVersion: String

    enum CodingKeys: String, CodingKey {
        case token
        case deviceToken
        case deviceTokenSnake = "device_token"
        case apnsToken
        case apnsTokenSnake = "apns_token"
        case platform
        case provider
        case bundleId
        case bundleIdSnake = "bundle_id"
        case appVersion
        case appVersionSnake = "app_version"
    }

    init(deviceToken: String, provider: String) {
        token = deviceToken
        self.deviceToken = deviceToken
        apnsToken = deviceToken
        platform = "ios"
        self.provider = provider
        bundleId = Bundle.main.bundleIdentifier ?? "Illumionix.Vixii"
        appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(token, forKey: .token)
        try container.encode(deviceToken, forKey: .deviceToken)
        try container.encode(deviceToken, forKey: .deviceTokenSnake)
        try container.encode(apnsToken, forKey: .apnsToken)
        try container.encode(apnsToken, forKey: .apnsTokenSnake)
        try container.encode(platform, forKey: .platform)
        try container.encode(provider, forKey: .provider)
        try container.encode(bundleId, forKey: .bundleId)
        try container.encode(bundleId, forKey: .bundleIdSnake)
        try container.encode(appVersion, forKey: .appVersion)
        try container.encode(appVersion, forKey: .appVersionSnake)
    }
}

private struct EmptyResponse: Codable {
    init() {}
}

private extension Data {
    mutating func appendString(_ string: String) {
        append(string.data(using: .utf8) ?? Data())
    }
}

extension UTType {
    static func mimeType(for pathExtension: String) -> String {
        if let type = UTType(filenameExtension: pathExtension),
           let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }
}
