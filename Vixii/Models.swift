import Foundation

private extension KeyedDecodingContainer {
    func decodeLossyInt(forKey key: Key) -> Int? {
        if let intValue = try? decode(Int.self, forKey: key) {
            return intValue
        }
        if let stringValue = try? decode(String.self, forKey: key) {
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let intValue = Int(trimmed) {
                return intValue
            }
            if let doubleValue = Double(trimmed) {
                return Int(doubleValue)
            }
            return nil
        }
        if let doubleValue = try? decode(Double.self, forKey: key) {
            return Int(doubleValue)
        }
        if let boolValue = try? decode(Bool.self, forKey: key) {
            return boolValue ? 1 : 0
        }
        return nil
    }

    func decodeLossyBool(forKey key: Key) -> Bool? {
        if let boolValue = try? decode(Bool.self, forKey: key) {
            return boolValue
        }
        if let intValue = try? decode(Int.self, forKey: key) {
            return intValue != 0
        }
        if let stringValue = try? decode(String.self, forKey: key) {
            let normalized = stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized == "1" || normalized == "true" || normalized == "yes" {
                return true
            }
            if normalized == "0" || normalized == "false" || normalized == "no" {
                return false
            }
        }
        return nil
    }

    func decodeLossyString(forKey key: Key) -> String? {
        if let stringValue = try? decode(String.self, forKey: key) {
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let intValue = try? decode(Int.self, forKey: key) {
            return String(intValue)
        }
        if let doubleValue = try? decode(Double.self, forKey: key) {
            return String(doubleValue)
        }
        if let boolValue = try? decode(Bool.self, forKey: key) {
            return boolValue ? "true" : "false"
        }
        return nil
    }
}

private func stablePositiveInt(from value: String) -> Int {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in value.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    let maxValue = UInt64(Int.max - 1)
    return Int((hash % maxValue) + 1)
}

struct APIUser: Codable, Identifiable, Hashable {
    let id: Int
    let username: String
    let email: String?
    let avatar: String?
    let status: String?
}

struct AuthResponse: Decodable {
    let token: String
    let user: APIUser
}

struct APIErrorResponse: Decodable {
    let error: String

    enum CodingKeys: String, CodingKey {
        case error
        case message
        case detail
    }

    init(error: String) {
        self.error = error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        error = try container.decodeIfPresent(String.self, forKey: .error)
            ?? container.decodeIfPresent(String.self, forKey: .message)
            ?? container.decodeIfPresent(String.self, forKey: .detail)
            ?? "Unknown server error"
    }
}

struct APIFileAttachment: Decodable, Hashable {
    let id: Int
    let filename: String
    let url: String
    let type: String?
    let size: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case fileId
        case fileIdSnake = "file_id"
        case filename
        case originalName = "originalname"
        case name
        case url
        case fileUrl = "file_url"
        case path
        case type
        case mimeType
        case mimetype
        case size
        case file
    }

    init(id: Int, filename: String, url: String, type: String?, size: Int?) {
        self.id = id
        self.filename = filename
        self.url = url
        self.type = type
        self.size = size
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let nested = try container.decodeIfPresent(APIFileAttachment.self, forKey: .file) {
            self = nested
            return
        }

        if let directID = try container.decodeIfPresent(Int.self, forKey: .id) {
            id = directID
        } else if let fileID = try container.decodeIfPresent(Int.self, forKey: .fileId) {
            id = fileID
        } else if let fileIDSnake = try container.decodeIfPresent(Int.self, forKey: .fileIdSnake) {
            id = fileIDSnake
        } else if let fileIDText = try container.decodeIfPresent(String.self, forKey: .fileId), let parsed = Int(fileIDText) {
            id = parsed
        } else if let idText = try container.decodeIfPresent(String.self, forKey: .id), let parsed = Int(idText) {
            id = parsed
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Upload response does not contain a valid file id")
        }

        filename = try container.decodeIfPresent(String.self, forKey: .filename)
            ?? container.decodeIfPresent(String.self, forKey: .originalName)
            ?? container.decodeIfPresent(String.self, forKey: .name)
            ?? "file-\(id)"

        url = try container.decodeIfPresent(String.self, forKey: .url)
            ?? container.decodeIfPresent(String.self, forKey: .fileUrl)
            ?? container.decodeIfPresent(String.self, forKey: .path)
            ?? ""

        type = try container.decodeIfPresent(String.self, forKey: .type)
            ?? container.decodeIfPresent(String.self, forKey: .mimeType)
            ?? container.decodeIfPresent(String.self, forKey: .mimetype)

        if let directSize = try container.decodeIfPresent(Int.self, forKey: .size) {
            size = directSize
        } else if let sizeText = try container.decodeIfPresent(String.self, forKey: .size), let parsed = Int(sizeText) {
            size = parsed
        } else {
            size = nil
        }
    }
}

struct ReplyPreview: Decodable, Hashable {
    let id: Int
    let author: String?
    let text: String?
    let isVoiceMessage: Bool?
    let file: APIFileAttachment?

    enum CodingKeys: String, CodingKey {
        case id
        case author
        case text
        case replyToAuthor = "reply_to_author"
        case replyToContent = "reply_to_content"
        case isVoiceMessage
        case isVoiceMessageSnake = "is_voice_message"
        case file
    }

    init(id: Int, author: String?, text: String?, isVoiceMessage: Bool?, file: APIFileAttachment?) {
        self.id = id
        self.author = author
        self.text = text
        self.isVoiceMessage = isVoiceMessage
        self.file = file
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyInt(forKey: .id) ?? 0
        author = try container.decodeIfPresent(String.self, forKey: .author)
            ?? container.decodeIfPresent(String.self, forKey: .replyToAuthor)
        text = try container.decodeIfPresent(String.self, forKey: .text)
            ?? container.decodeIfPresent(String.self, forKey: .replyToContent)
        isVoiceMessage = container.decodeLossyBool(forKey: .isVoiceMessage)
            ?? container.decodeLossyBool(forKey: .isVoiceMessageSnake)
        file = try container.decodeIfPresent(APIFileAttachment.self, forKey: .file)
    }
}

struct ReactionSummary: Decodable, Hashable, Identifiable {
    var id: String { "\(emoji)-\(count)" }
    let emoji: String
    let count: Int
    let users: String?
}

struct DirectMessage: Decodable, Identifiable, Hashable {
    let id: Int
    let content: String
    let senderID: Int
    let receiverID: Int
    let username: String?
    let avatar: String?
    let createdAt: String
    let reactions: [ReactionSummary]
    let file: APIFileAttachment?
    let edited: Bool
    let originalContent: String?
    let replyTo: ReplyPreview?

    enum CodingKeys: String, CodingKey {
        case id
        case content
        case text
        case senderID = "sender_id"
        case senderIDCamel = "senderId"
        case receiverID = "receiver_id"
        case receiverIDCamel = "receiverId"
        case username
        case author
        case avatar
        case createdAt = "created_at"
        case timestamp
        case reactions
        case file
        case attachment
        case attachments
        case fileId
        case fileIdSnake = "file_id"
        case fileUrl
        case fileUrlSnake = "file_url"
        case filename
        case fileName
        case type
        case mimeType
        case mimetype
        case size
        case edited
        case isEdited = "is_edited"
        case originalContent
        case originalContentSnake = "original_content"
        case replyTo
    }

    init(
        id: Int,
        content: String,
        senderID: Int,
        receiverID: Int,
        username: String?,
        avatar: String?,
        createdAt: String,
        reactions: [ReactionSummary],
        file: APIFileAttachment?,
        edited: Bool,
        originalContent: String?,
        replyTo: ReplyPreview?
    ) {
        self.id = id
        self.content = content
        self.senderID = senderID
        self.receiverID = receiverID
        self.username = username
        self.avatar = avatar
        self.createdAt = createdAt
        self.reactions = reactions
        self.file = file
        self.edited = edited
        self.originalContent = originalContent
        self.replyTo = replyTo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        content = try container.decodeIfPresent(String.self, forKey: .content)
            ?? container.decodeIfPresent(String.self, forKey: .text)
            ?? ""
        senderID = try container.decodeIfPresent(Int.self, forKey: .senderID)
            ?? container.decodeIfPresent(Int.self, forKey: .senderIDCamel)
            ?? 0
        receiverID = try container.decodeIfPresent(Int.self, forKey: .receiverID)
            ?? container.decodeIfPresent(Int.self, forKey: .receiverIDCamel)
            ?? 0
        username = try container.decodeIfPresent(String.self, forKey: .username)
            ?? container.decodeIfPresent(String.self, forKey: .author)
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
            ?? container.decodeIfPresent(String.self, forKey: .timestamp)
            ?? ""
        reactions = try container.decodeIfPresent([ReactionSummary].self, forKey: .reactions) ?? []

        let nestedFile = try container.decodeIfPresent(APIFileAttachment.self, forKey: .file)
            ?? container.decodeIfPresent(APIFileAttachment.self, forKey: .attachment)
            ?? container.decodeIfPresent([APIFileAttachment].self, forKey: .attachments)?.first

        if let nestedFile {
            file = nestedFile
        } else {
            let decodedFileId = try container.decodeIfPresent(Int.self, forKey: .fileId)
                ?? container.decodeIfPresent(Int.self, forKey: .fileIdSnake)
                ?? (try container.decodeIfPresent(String.self, forKey: .fileId)).flatMap(Int.init)
                ?? (try container.decodeIfPresent(String.self, forKey: .fileIdSnake)).flatMap(Int.init)

            let decodedURL = try container.decodeIfPresent(String.self, forKey: .fileUrl)
                ?? container.decodeIfPresent(String.self, forKey: .fileUrlSnake)
                ?? ""

            if let decodedFileId {
                let decodedFilename = try container.decodeIfPresent(String.self, forKey: .filename)
                    ?? container.decodeIfPresent(String.self, forKey: .fileName)
                    ?? URL(fileURLWithPath: decodedURL).lastPathComponent
                let decodedType = try container.decodeIfPresent(String.self, forKey: .type)
                    ?? container.decodeIfPresent(String.self, forKey: .mimeType)
                    ?? container.decodeIfPresent(String.self, forKey: .mimetype)
                let decodedSize = try container.decodeIfPresent(Int.self, forKey: .size)
                    ?? (try container.decodeIfPresent(String.self, forKey: .size)).flatMap(Int.init)

                file = APIFileAttachment(
                    id: decodedFileId,
                    filename: decodedFilename.isEmpty ? "file-\(decodedFileId)" : decodedFilename,
                    url: decodedURL,
                    type: decodedType,
                    size: decodedSize
                )
            } else if !decodedURL.isEmpty {
                let decodedFilename = try container.decodeIfPresent(String.self, forKey: .filename)
                    ?? container.decodeIfPresent(String.self, forKey: .fileName)
                    ?? URL(fileURLWithPath: decodedURL).lastPathComponent
                let decodedType = try container.decodeIfPresent(String.self, forKey: .type)
                    ?? container.decodeIfPresent(String.self, forKey: .mimeType)
                    ?? container.decodeIfPresent(String.self, forKey: .mimetype)
                let decodedSize = try container.decodeIfPresent(Int.self, forKey: .size)
                    ?? (try container.decodeIfPresent(String.self, forKey: .size)).flatMap(Int.init)

                file = APIFileAttachment(
                    id: id,
                    filename: decodedFilename.isEmpty ? "file-\(id)" : decodedFilename,
                    url: decodedURL,
                    type: decodedType,
                    size: decodedSize
                )
            } else {
                file = nil
            }
        }

        edited = try container.decodeIfPresent(Bool.self, forKey: .edited)
            ?? container.decodeIfPresent(Bool.self, forKey: .isEdited)
            ?? false
        originalContent = try container.decodeIfPresent(String.self, forKey: .originalContent)
            ?? container.decodeIfPresent(String.self, forKey: .originalContentSnake)
        replyTo = try container.decodeIfPresent(ReplyPreview.self, forKey: .replyTo)
    }
}

struct ChannelModel: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let description: String?
    let type: String?
    let isSystem: Int?
    let ownerID: Int?
    let subscriberCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case type
        case isSystem = "is_system"
        case isSystemCamel = "isSystem"
        case ownerID = "owner_id"
        case ownerIDCamel = "ownerId"
        case subscriberCount
        case subscriberCountSnake = "subscriber_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "News"
        let rawID = (try? container.decode(String.self, forKey: .id))
        id = container.decodeLossyInt(forKey: .id)
            ?? rawID.map(stablePositiveInt)
            ?? stablePositiveInt(from: name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        isSystem = container.decodeLossyInt(forKey: .isSystem)
            ?? container.decodeLossyInt(forKey: .isSystemCamel)
        ownerID = container.decodeLossyInt(forKey: .ownerID)
            ?? container.decodeLossyInt(forKey: .ownerIDCamel)
        subscriberCount = container.decodeLossyInt(forKey: .subscriberCount)
            ?? container.decodeLossyInt(forKey: .subscriberCountSnake)
    }
}

struct ChannelMessage: Decodable, Identifiable, Hashable {
    let id: Int
    let content: String
    let channelID: Int
    let senderID: Int
    let createdAt: String
    let username: String?
    let avatar: String?
    let edited: Bool
    let originalContent: String?
    let replyTo: ReplyPreview?

    enum CodingKeys: String, CodingKey {
        case id
        case content
        case text
        case channelID = "channel_id"
        case channelIDCamel = "channelId"
        case senderID = "sender_id"
        case senderIDCamel = "senderId"
        case createdAt = "created_at"
        case createdAtCamel = "createdAt"
        case timestamp
        case username
        case author
        case avatar
        case edited
        case isEdited = "is_edited"
        case originalContent
        case originalContentSnake = "original_content"
        case replyTo
        case replyToID = "reply_to_id"
        case replyToAuthor = "reply_to_author"
        case replyToContent = "reply_to_content"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decodeIfPresent(String.self, forKey: .content)
            ?? container.decodeIfPresent(String.self, forKey: .text)
            ?? ""
        channelID = container.decodeLossyInt(forKey: .channelID)
            ?? container.decodeLossyInt(forKey: .channelIDCamel)
            ?? 0
        senderID = container.decodeLossyInt(forKey: .senderID)
            ?? container.decodeLossyInt(forKey: .senderIDCamel)
            ?? 0
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
            ?? container.decodeIfPresent(String.self, forKey: .createdAtCamel)
            ?? container.decodeIfPresent(String.self, forKey: .timestamp)
            ?? ""
        let rawID = (try? container.decode(String.self, forKey: .id))
        id = container.decodeLossyInt(forKey: .id)
            ?? rawID.map(stablePositiveInt)
            ?? stablePositiveInt(from: "\(channelID)|\(senderID)|\(createdAt)|\(content)")
        username = try container.decodeIfPresent(String.self, forKey: .username)
            ?? container.decodeIfPresent(String.self, forKey: .author)
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar)
        edited = container.decodeLossyBool(forKey: .edited)
            ?? container.decodeLossyBool(forKey: .isEdited)
            ?? false
        originalContent = try container.decodeIfPresent(String.self, forKey: .originalContent)
            ?? container.decodeIfPresent(String.self, forKey: .originalContentSnake)
        if let decodedReply = try? container.decodeIfPresent(ReplyPreview.self, forKey: .replyTo) {
            replyTo = decodedReply
        } else if let fallbackReplyID = container.decodeLossyInt(forKey: .replyToID) {
            replyTo = ReplyPreview(
                id: fallbackReplyID,
                author: try container.decodeIfPresent(String.self, forKey: .replyToAuthor),
                text: try container.decodeIfPresent(String.self, forKey: .replyToContent),
                isVoiceMessage: nil,
                file: nil
            )
        } else {
            replyTo = nil
        }
    }
}

struct FriendRequestUser: Decodable, Identifiable, Hashable {
    let id: Int
    let username: String
    let email: String?
    let avatar: String?
    let status: String?

    var asAPIUser: APIUser {
        APIUser(id: id, username: username, email: email, avatar: avatar, status: status)
    }
}

struct NotificationItem: Decodable, Identifiable, Hashable {
    let id: Int
    let userId: Int
    let fromUserId: Int?
    let fromUsername: String?
    let fromAvatar: String?
    let type: String
    let callType: String?
    let content: String?
    let read: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case userIdCamel = "userId"
        case fromUserId = "from_user_id"
        case fromUserIdCamel = "fromUserId"
        case fromUsername = "from_username"
        case fromUsernameCamel = "fromUsername"
        case username
        case fromAvatar = "from_avatar"
        case fromAvatarCamel = "fromAvatar"
        case avatar
        case type
        case callType = "call_type"
        case callTypeCamel = "callType"
        case content
        case text
        case message
        case body
        case read
        case createdAt = "created_at"
        case createdAtCamel = "createdAt"
        case timestamp
        case date
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedUserID = container.decodeLossyInt(forKey: .userId)
            ?? container.decodeLossyInt(forKey: .userIdCamel)
        let decodedFromUserID = container.decodeLossyInt(forKey: .fromUserId)
            ?? container.decodeLossyInt(forKey: .fromUserIdCamel)
            ?? decodedUserID
        userId = decodedUserID ?? decodedFromUserID ?? 0
        fromUserId = decodedFromUserID

        fromUsername = container.decodeLossyString(forKey: .fromUsername)
            ?? container.decodeLossyString(forKey: .fromUsernameCamel)
            ?? container.decodeLossyString(forKey: .username)
        fromAvatar = container.decodeLossyString(forKey: .fromAvatar)
            ?? container.decodeLossyString(forKey: .fromAvatarCamel)
            ?? container.decodeLossyString(forKey: .avatar)
        let decodedType = container.decodeLossyString(forKey: .type) ?? "message"
        if decodedType == "missed_call" {
            type = "missed-call"
        } else {
            type = decodedType
        }
        callType = container.decodeLossyString(forKey: .callType)
            ?? container.decodeLossyString(forKey: .callTypeCamel)
        content = container.decodeLossyString(forKey: .content)
            ?? container.decodeLossyString(forKey: .text)
            ?? container.decodeLossyString(forKey: .message)
            ?? container.decodeLossyString(forKey: .body)
        read = container.decodeLossyBool(forKey: .read) ?? false
        createdAt = container.decodeLossyString(forKey: .createdAt)
            ?? container.decodeLossyString(forKey: .createdAtCamel)
            ?? container.decodeLossyString(forKey: .timestamp)
            ?? container.decodeLossyString(forKey: .date)
            ?? ""
        let rawID = container.decodeLossyString(forKey: .id)
        id = container.decodeLossyInt(forKey: .id)
            ?? rawID.map(stablePositiveInt)
            ?? stablePositiveInt(from: "\(userId)|\(fromUserId ?? 0)|\(type)|\(createdAt)|\(content ?? "")")
    }
}

struct NotificationsResponse: Decodable {
    let notifications: [NotificationItem]
    let unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case notifications
        case data
        case items
        case results
        case unreadCount
        case unreadCountSnake = "unread_count"
        case unread
    }

    init(notifications: [NotificationItem], unreadCount: Int) {
        self.notifications = notifications
        self.unreadCount = unreadCount
    }

    init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let rawItems = try? singleValue.decode([NotificationItem].self) {
            notifications = rawItems
            unreadCount = rawItems.filter { !$0.read }.count
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let directNotifications = try container.decodeIfPresent([NotificationItem].self, forKey: .notifications)
        let itemsNotifications = try container.decodeIfPresent([NotificationItem].self, forKey: .items)
        let resultNotifications = try container.decodeIfPresent([NotificationItem].self, forKey: .results)
        let nestedDataObject = try? container.decode(NotificationsResponse.self, forKey: .data)
        let nestedDataArray = try? container.decode([NotificationItem].self, forKey: .data)

        notifications = directNotifications
            ?? nestedDataObject?.notifications
            ?? nestedDataArray
            ?? itemsNotifications
            ?? resultNotifications
            ?? []

        unreadCount = container.decodeLossyInt(forKey: .unreadCount)
            ?? container.decodeLossyInt(forKey: .unreadCountSnake)
            ?? container.decodeLossyInt(forKey: .unread)
            ?? nestedDataObject?.unreadCount
            ?? notifications.filter { !$0.read }.count
    }
}

struct MessageReactionsResponse: Decodable {
    let messageId: Int
    let reactions: [ReactionSummary]

    enum CodingKeys: String, CodingKey {
        case messageId
        case messageIdSnake = "message_id"
        case reactions
    }

    init(messageId: Int, reactions: [ReactionSummary]) {
        self.messageId = messageId
        self.reactions = reactions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messageId = try container.decodeIfPresent(Int.self, forKey: .messageId)
            ?? container.decodeIfPresent(Int.self, forKey: .messageIdSnake)
            ?? 0
        reactions = try container.decodeIfPresent([ReactionSummary].self, forKey: .reactions) ?? []
    }
}

struct SendMessageFilePayload: Encodable {
    let id: Int
    let filename: String
    let url: String
    let type: String?
    let size: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case fileId = "fileId"
        case fileIdSnake = "file_id"
        case attachmentId = "attachment_id"
        case filename
        case url
        case path
        case type
        case mimeType
        case mimetype
        case size
    }

    init(_ attachment: APIFileAttachment) {
        id = attachment.id
        filename = attachment.filename
        url = attachment.url
        type = attachment.type
        size = attachment.size
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(id, forKey: .fileId)
        try container.encode(id, forKey: .fileIdSnake)
        try container.encode(id, forKey: .attachmentId)
        try container.encode(filename, forKey: .filename)
        try container.encode(url, forKey: .url)
        try container.encode(url, forKey: .path)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(type, forKey: .mimeType)
        try container.encodeIfPresent(type, forKey: .mimetype)
        try container.encodeIfPresent(size, forKey: .size)
    }
}

struct SendMessageReplyPayload: Encodable {
    let id: Int
}

struct SendMessageSocketEnvelope: Encodable {
    let text: String
    let content: String
    let timestamp: String
    let file: SendMessageFilePayload?
    let fileId: Int?
    let replyTo: SendMessageReplyPayload?
    let isVoiceMessage: Bool?

    enum CodingKeys: String, CodingKey {
        case text
        case content
        case timestamp
        case file
        case fileId
        case fileIdSnake = "file_id"
        case attachmentId = "attachment_id"
        case attachment
        case attachments
        case filename
        case fileUrl = "file_url"
        case url
        case type
        case mimeType
        case mimetype
        case size
        case replyTo
        case isVoiceMessage
        case isVoiceMessageSnake = "is_voice_message"
        case voiceMessage
        case voiceMessageSnake = "voice_message"
        case messageType
        case folder
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(content, forKey: .content)
        try container.encode(timestamp, forKey: .timestamp)

        if let file {
            try container.encode(file, forKey: .file)
        } else if let fileId {
            // Some socket/HTTP handlers still accept numeric file in message payload.
            try container.encode(fileId, forKey: .file)
        }

        if let fileId {
            try container.encode(fileId, forKey: .fileId)
            try container.encode(fileId, forKey: .fileIdSnake)
            try container.encode(fileId, forKey: .attachmentId)
        }

        if let file {
            try container.encode(file, forKey: .attachment)
            try container.encode([file], forKey: .attachments)
            try container.encode(file.filename, forKey: .filename)
            try container.encode(file.url, forKey: .url)
            try container.encode(file.url, forKey: .fileUrl)
            try container.encodeIfPresent(file.type, forKey: .type)
            try container.encodeIfPresent(file.type, forKey: .mimeType)
            try container.encodeIfPresent(file.type, forKey: .mimetype)
            try container.encodeIfPresent(file.size, forKey: .size)
        }

        try container.encodeIfPresent(replyTo, forKey: .replyTo)
        if let isVoiceMessage {
            try container.encode(isVoiceMessage, forKey: .isVoiceMessage)
            try container.encode(isVoiceMessage, forKey: .isVoiceMessageSnake)
            try container.encode(isVoiceMessage, forKey: .voiceMessage)
            try container.encode(isVoiceMessage, forKey: .voiceMessageSnake)
            try container.encode("voice", forKey: .messageType)
            try container.encode("voice_messages", forKey: .folder)
        }
    }
}

struct SendMessageRequest: Encodable {
    let text: String
    let content: String?
    let timestamp: String
    let receiverId: Int?
    let fileId: Int?
    let file: SendMessageFilePayload?
    let replyToId: Int?
    let isVoiceMessage: Bool?

    enum CodingKeys: String, CodingKey {
        case text
        case message
        case content
        case timestamp
        case receiverId
        case receiverIdSnake = "receiver_id"
        case dmId
        case dmIdSnake = "dm_id"
        case fileId
        case fileIdSnake = "file_id"
        case file
        case attachment
        case attachments
        case attachmentId = "attachment_id"
        case filename
        case fileUrl = "file_url"
        case url
        case type
        case mimeType
        case mimetype
        case size
        case replyToId
        case replyToIdSnake = "reply_to_id"
        case isVoiceMessage
        case isVoiceMessageSnake = "is_voice_message"
        case voiceMessage
        case voiceMessageSnake = "voice_message"
        case messageType
        case folder
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        if let content {
            try container.encode(content, forKey: .content)
        }
        try container.encode(timestamp, forKey: .timestamp)

        if let receiverId {
            try container.encode(receiverId, forKey: .receiverId)
            try container.encode(receiverId, forKey: .receiverIdSnake)
            try container.encode(receiverId, forKey: .dmId)
            try container.encode(receiverId, forKey: .dmIdSnake)
        }

        if let fileId {
            try container.encode(fileId, forKey: .fileId)
            try container.encode(fileId, forKey: .fileIdSnake)
            try container.encode(fileId, forKey: .attachmentId)
        }

        if let file {
            try container.encode(file, forKey: .file)
        } else if let fileId {
            // Fallback for backends that still expect numeric top-level "file".
            try container.encode(fileId, forKey: .file)
        }

        if let file {
            // Additional aliases for backends that parse attachment objects from other keys.
            try container.encode(file, forKey: .attachment)
            try container.encode([file], forKey: .attachments)
            try container.encode(file.filename, forKey: .filename)
            try container.encode(file.url, forKey: .url)
            try container.encode(file.url, forKey: .fileUrl)
            try container.encodeIfPresent(file.type, forKey: .type)
            try container.encodeIfPresent(file.type, forKey: .mimeType)
            try container.encodeIfPresent(file.type, forKey: .mimetype)
            try container.encodeIfPresent(file.size, forKey: .size)
        }

        let envelope = SendMessageSocketEnvelope(
            text: text,
            content: content ?? text,
            timestamp: timestamp,
            file: file,
            fileId: fileId,
            replyTo: replyToId.map { SendMessageReplyPayload(id: $0) },
            isVoiceMessage: isVoiceMessage
        )
        try container.encode(envelope, forKey: .message)

        if let replyToId {
            try container.encode(replyToId, forKey: .replyToId)
            try container.encode(replyToId, forKey: .replyToIdSnake)
        }

        if let isVoiceMessage {
            try container.encode(isVoiceMessage, forKey: .isVoiceMessage)
            try container.encode(isVoiceMessage, forKey: .isVoiceMessageSnake)
            try container.encode(isVoiceMessage, forKey: .voiceMessage)
            try container.encode(isVoiceMessage, forKey: .voiceMessageSnake)
            try container.encode("voice", forKey: .messageType)
            try container.encode("voice_messages", forKey: .folder)
        }
    }
}

struct UpdateMessageRequest: Codable {
    let text: String
}

struct ReactionRequest: Codable {
    let emoji: String
}

struct FriendActionRequest: Codable {
    let friendId: Int
}

struct MarkUserReadRequest: Codable {
    let fromUserId: Int
}

struct UpdateUserProfileRequest: Codable {
    let username: String?
    let email: String?
    let avatar: String?
    let status: String?
}

struct CreateServerRequest: Codable {
    let name: String
    let description: String?
}

struct ChannelMessageRequest: Codable {
    let content: String
    let replyToId: Int?
}

struct APIServer: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let description: String?
    let ownerId: Int?
    let ownerUsername: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case ownerId = "owner_id"
        case ownerIdCamel = "ownerId"
        case ownerUsername = "owner_username"
        case ownerUsernameCamel = "ownerUsername"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Server"
        description = try container.decodeIfPresent(String.self, forKey: .description)
        ownerId = try container.decodeIfPresent(Int.self, forKey: .ownerId)
            ?? container.decodeIfPresent(Int.self, forKey: .ownerIdCamel)
        ownerUsername = try container.decodeIfPresent(String.self, forKey: .ownerUsername)
            ?? container.decodeIfPresent(String.self, forKey: .ownerUsernameCamel)
    }
}

struct LinkPreviewMetadata: Decodable, Hashable {
    let url: String?
    let title: String?
    let description: String?
    let image: String?
    let siteName: String?
    let favicon: String?

    enum CodingKeys: String, CodingKey {
        case url
        case title
        case description
        case image
        case siteName
        case siteNameSnake = "site_name"
        case favicon
    }

    init(url: String?, title: String?, description: String?, image: String?, siteName: String?, favicon: String?) {
        self.url = url
        self.title = title
        self.description = description
        self.image = image
        self.siteName = siteName
        self.favicon = favicon
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        image = try container.decodeIfPresent(String.self, forKey: .image)
        siteName = try container.decodeIfPresent(String.self, forKey: .siteName)
            ?? container.decodeIfPresent(String.self, forKey: .siteNameSnake)
        favicon = try container.decodeIfPresent(String.self, forKey: .favicon)
    }
}

struct TranscriptionResult: Decodable {
    let text: String
    let language: String?
}
