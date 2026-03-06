import Foundation
import CallKit
import AVFoundation
import UIKit

extension Notification.Name {
    static let voxiiIncomingCallDidArrive = Notification.Name("voxiiIncomingCallDidArrive")
    static let voxiiIncomingCallAnswerRequested = Notification.Name("voxiiIncomingCallAnswerRequested")
}

struct IncomingCallPayload: Identifiable, Hashable, Codable {
    let id: String
    let callerId: Int
    let callerUsername: String
    let callerAvatar: String?
    let callerSocketId: String?
    let callType: String

    var isVideoCall: Bool {
        callType.lowercased() == "video"
    }

    static func fromRemoteNotification(userInfo: [AnyHashable: Any]) -> IncomingCallPayload? {
        let root = stringifyKeys(userInfo)
        return fromDictionary(root)
    }

    static func fromDictionary(_ root: [String: Any]) -> IncomingCallPayload? {
        let candidates = [
            root,
            dictionary(from: root["call"]),
            dictionary(from: root["data"]),
            dictionary(from: root["payload"])
        ].compactMap { $0 }

        for candidate in candidates {
            if let parsed = parseCandidate(candidate, root: root) {
                return parsed
            }
        }
        return nil
    }

    private static func parseCandidate(_ candidate: [String: Any], root: [String: Any]) -> IncomingCallPayload? {
        let from = dictionary(from: candidate["from"]) ?? dictionary(from: root["from"]) ?? [:]
        let aps = dictionary(from: root["aps"]) ?? [:]

        let eventType = normalizedLowercasedString(
            firstNonEmptyString(
                candidate["event"],
                candidate["notificationType"],
                candidate["type"],
                root["event"],
                root["notificationType"],
                root["type"],
                aps["category"]
            )
        )

        let parsedCallType = normalizedCallType(
            firstNonEmptyString(
                candidate["callType"],
                candidate["call_type"],
                root["callType"],
                root["call_type"],
                candidate["media"],
                root["media"]
            )
        )

        let callerId = parseInt(
            candidate["callerId"]
                ?? candidate["caller_id"]
                ?? candidate["fromUserId"]
                ?? candidate["from_user_id"]
                ?? from["id"]
        )

        let rawCallerUsername = firstNonEmptyString(
            candidate["callerUsername"],
            candidate["caller_username"],
            candidate["fromUsername"],
            candidate["from_username"],
            candidate["username"],
            from["username"],
            aps["title"]
        )
        let callerUsername = rawCallerUsername ?? "Unknown"

        let callerAvatar = firstNonEmptyString(
            candidate["callerAvatar"],
            candidate["caller_avatar"],
            candidate["avatar"],
            from["avatar"]
        )

        let callerSocketId = firstNonEmptyString(
            candidate["callerSocketId"],
            candidate["caller_socket_id"],
            candidate["socketId"],
            from["socketId"],
            from["socket_id"]
        )

        let explicitEventId = firstNonEmptyString(
            candidate["eventId"],
            candidate["event_id"],
            candidate["callId"],
            candidate["call_id"],
            candidate["id"],
            root["eventId"],
            root["event_id"],
            root["callId"],
            root["call_id"]
        )

        let fallbackEventId = "\(callerId)-\(callerSocketId ?? "no-socket")-\(Int(Date().timeIntervalSince1970))"
        let eventId = explicitEventId ?? fallbackEventId
        let eventIdLooksLikeCall = normalizedLowercasedString(explicitEventId).contains("call")

        let typeLooksLikeCall = eventType.contains("call")
            || eventType == "incoming"
            || eventType == "ringing"
            || eventType == "video"
            || eventType == "audio"
            || eventType == "voip"

        let hasIdentity = callerId > 0 || rawCallerUsername != nil
        let hasCallFields = callerSocketId != nil
            || parsedCallType != nil
            || eventIdLooksLikeCall

        guard (typeLooksLikeCall && hasIdentity) || hasCallFields else {
            return nil
        }

        return IncomingCallPayload(
            id: eventId,
            callerId: callerId,
            callerUsername: callerUsername,
            callerAvatar: callerAvatar,
            callerSocketId: callerSocketId,
            callType: parsedCallType ?? "video"
        )
    }

    private static func normalizedCallType(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let raw = normalizedLowercasedString(value)
        guard !raw.isEmpty else {
            return nil
        }
        if raw.contains("video") {
            return "video"
        }
        if raw.contains("audio") || raw.contains("voice") {
            return "audio"
        }
        return nil
    }

    private static func normalizedLowercasedString(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private static func parseInt(_ value: Any?) -> Int {
        if let intValue = value as? Int {
            return intValue
        }
        if let doubleValue = value as? Double {
            return Int(doubleValue)
        }
        if let stringValue = value as? String {
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let intValue = Int(trimmed) {
                return intValue
            }
        }
        return 0
    }

    private static func firstNonEmptyString(_ values: Any?...) -> String? {
        for value in values {
            if let stringValue = value as? String {
                let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private static func stringifyKeys(_ value: [AnyHashable: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        result.reserveCapacity(value.count)
        for (key, value) in value {
            if let stringKey = key as? String {
                result[stringKey] = value
            } else {
                result[String(describing: key)] = value
            }
        }
        return result
    }

    private static func dictionary(from value: Any?) -> [String: Any]? {
        if let object = value as? [String: Any] {
            return object
        }
        if let object = value as? [AnyHashable: Any] {
            return stringifyKeys(object)
        }
        return nil
    }
}

struct IncomingMessageNotificationPayload: Identifiable, Hashable {
    let id: String
    let title: String
    let body: String

    static func fromRemoteNotification(userInfo: [AnyHashable: Any]) -> IncomingMessageNotificationPayload? {
        let root = stringifyKeys(userInfo)
        return fromDictionary(root)
    }

    static func fromDictionary(_ root: [String: Any]) -> IncomingMessageNotificationPayload? {
        if IncomingCallPayload.fromDictionary(root) != nil {
            return nil
        }

        let aps = dictionary(from: root["aps"]) ?? [:]
        let apsAlert = apsAlertData(from: aps["alert"])
        let candidates = [
            root,
            dictionary(from: root["data"]),
            dictionary(from: root["payload"]),
            dictionary(from: root["message"]),
            dictionary(from: root["notification"])
        ].compactMap { $0 }

        for candidate in candidates {
            let eventType = normalizedLowercasedString(
                firstNonEmptyString(
                    candidate["event"],
                    candidate["notificationType"],
                    candidate["type"],
                    root["event"],
                    root["notificationType"],
                    root["type"]
                )
            )

            let body = firstNonEmptyString(
                candidate["body"],
                candidate["text"],
                candidate["content"],
                dictionary(from: candidate["message"])?["body"],
                dictionary(from: candidate["message"])?["text"],
                dictionary(from: candidate["message"])?["content"],
                root["body"],
                root["text"],
                root["content"],
                apsAlert.body
            )

            let title = firstNonEmptyString(
                candidate["title"],
                candidate["senderUsername"],
                candidate["sender_username"],
                candidate["fromUsername"],
                candidate["from_username"],
                dictionary(from: candidate["sender"])?["username"],
                dictionary(from: candidate["from"])?["username"],
                root["title"],
                apsAlert.title
            ) ?? "Voxii"

            let looksLikeMessageEvent = eventType.contains("message")
                || eventType.contains("dm")
                || eventType.contains("chat")
                || eventType.contains("notification")
                || eventType == "new-dm"
                || eventType == "new_message"
                || eventType == "new-message"
                || eventType == "direct_message"

            let hasDisplayableBody = body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            guard looksLikeMessageEvent || hasDisplayableBody else {
                continue
            }

            let messageId = firstNonEmptyString(
                candidate["messageId"],
                candidate["message_id"],
                dictionary(from: candidate["message"])?["id"],
                root["messageId"],
                root["message_id"],
                root["id"]
            ) ?? "msg-\(Int(Date().timeIntervalSince1970 * 1000))"

            return IncomingMessageNotificationPayload(
                id: messageId,
                title: title,
                body: body ?? "You have a new message"
            )
        }

        return nil
    }

    private static func apsAlertData(from value: Any?) -> (title: String?, body: String?) {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return (nil, trimmed.isEmpty ? nil : trimmed)
        }
        if let object = dictionary(from: value) {
            let title = firstNonEmptyString(object["title"])
            let body = firstNonEmptyString(object["body"])
            return (title, body)
        }
        return (nil, nil)
    }

    private static func normalizedLowercasedString(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private static func firstNonEmptyString(_ values: Any?...) -> String? {
        for value in values {
            if let stringValue = value as? String {
                let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private static func stringifyKeys(_ value: [AnyHashable: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        result.reserveCapacity(value.count)
        for (key, value) in value {
            if let stringKey = key as? String {
                result[stringKey] = value
            } else {
                result[String(describing: key)] = value
            }
        }
        return result
    }

    private static func dictionary(from value: Any?) -> [String: Any]? {
        if let object = value as? [String: Any] {
            return object
        }
        if let object = value as? [AnyHashable: Any] {
            return stringifyKeys(object)
        }
        return nil
    }
}

final class VoxiiCallKitManager: NSObject, CXProviderDelegate {
    static let shared = VoxiiCallKitManager()

    private let provider: CXProvider
    private let callController = CXCallController()
    private var uuidByEventID: [String: UUID] = [:]
    private var payloadByUUID: [UUID: IncomingCallPayload] = [:]
    private var pendingIncomingPayload: IncomingCallPayload?
    private var pendingAnswerPayload: IncomingCallPayload?

    override private init() {
        let configuration = CXProviderConfiguration()
        configuration.supportedHandleTypes = [.generic]
        configuration.includesCallsInRecents = false
        configuration.maximumCallsPerCallGroup = 1
        configuration.maximumCallGroups = 1
        configuration.supportsVideo = true
        configuration.ringtoneSound = nil

        provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    func reportIncomingCall(_ payload: IncomingCallPayload) {
        if let existingUUID = uuidByEventID[payload.id] {
            payloadByUUID[existingUUID] = payload
            notifyIncoming(payload)
            return
        }

        let uuid = UUID()
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: payload.callerUsername)
        update.localizedCallerName = payload.callerUsername
        update.hasVideo = payload.isVideoCall
        update.supportsDTMF = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsHolding = false

        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            guard let self else { return }
            if let error {
                print("[CallKit] reportNewIncomingCall failed: \(error.localizedDescription)")
                self.notifyIncoming(payload)
                return
            }
            self.uuidByEventID[payload.id] = uuid
            self.payloadByUUID[uuid] = payload
            self.notifyIncoming(payload)
        }
    }

    func receiveAnsweredCallPayload(_ payload: IncomingCallPayload) {
        pendingAnswerPayload = payload
        NotificationCenter.default.post(name: .voxiiIncomingCallAnswerRequested, object: payload)
    }

    func endCall(eventID: String, reason: CXCallEndedReason = .remoteEnded) {
        guard let uuid = uuidByEventID[eventID] else {
            return
        }
        provider.reportCall(with: uuid, endedAt: Date(), reason: reason)
        clearCall(uuid: uuid)
    }

    func consumePendingIncomingPayload() -> IncomingCallPayload? {
        let payload = pendingIncomingPayload
        pendingIncomingPayload = nil
        return payload
    }

    func consumePendingAnswerPayload() -> IncomingCallPayload? {
        let payload = pendingAnswerPayload
        pendingAnswerPayload = nil
        return payload
    }

    private func notifyIncoming(_ payload: IncomingCallPayload) {
        pendingIncomingPayload = payload
        NotificationCenter.default.post(name: .voxiiIncomingCallDidArrive, object: payload)
    }

    private func clearCall(uuid: UUID) {
        if let payload = payloadByUUID.removeValue(forKey: uuid) {
            uuidByEventID[payload.id] = nil
        }
    }

    func providerDidReset(_ provider: CXProvider) {
        payloadByUUID.removeAll()
        uuidByEventID.removeAll()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        defer { action.fulfill() }
        guard let payload = payloadByUUID[action.callUUID] else {
            return
        }
        receiveAnsweredCallPayload(payload)
        activateApplicationForCallIfPossible()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        defer { action.fulfill() }
        clearCall(uuid: action.callUUID)
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) { }
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) { }

    private func activateApplicationForCallIfPossible() {
        DispatchQueue.main.async {
            guard UIApplication.shared.applicationState != .active else {
                return
            }

            let preferredScene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundInactive || $0.activationState == .background }

            UIApplication.shared.requestSceneSessionActivation(
                preferredScene?.session,
                userActivity: nil,
                options: nil
            ) { error in
                print("[CallKit] Failed to activate app for answered call: \(error.localizedDescription)")
            }
        }
    }
}
