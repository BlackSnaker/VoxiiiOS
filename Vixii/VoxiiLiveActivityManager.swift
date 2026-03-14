import ActivityKit
import Foundation

@MainActor
final class VoxiiLiveActivityManager {
    static let shared = VoxiiLiveActivityManager()

    private var messageDismissTasks: [String: Task<Void, Never>] = [:]

    private init() {}

    var canPresentLiveActivities: Bool {
        guard #available(iOS 16.1, *) else {
            return false
        }
        return ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func presentIncomingMessage(
        _ payload: IncomingMessageNotificationPayload,
        preferAlertPresentation: Bool = false
    ) async {
        guard #available(iOS 16.1, *), canPresentLiveActivities else {
            print("[LiveActivity][Message] Skipped: Live Activities are unavailable")
            return
        }

        let conversationID = payload.conversationID
            ?? payload.senderID.map { "dm-\($0)" }
            ?? "msg-\(payload.id)"

        let attributes = VoxiiMessageActivityAttributes(
            conversationID: conversationID,
            avatarText: payload.title,
            deepLink: "voxii://messages/\(conversationID)"
        )
        let state = VoxiiMessageActivityAttributes.ContentState(
            senderName: payload.title,
            previewText: payload.body,
            statusText: localizedMessageStatus(),
            unreadCount: max(payload.unreadCount ?? 1, 1),
            receivedAt: Date()
        )
        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(90),
            relevanceScore: 0.9
        )
        let alertConfiguration = messageAlertConfiguration(
            title: payload.title,
            body: payload.body,
            preferAlertPresentation: preferAlertPresentation
        )

        if let existing = Activity<VoxiiMessageActivityAttributes>.activities.first(where: { $0.attributes.conversationID == conversationID }) {
            await updateMessageActivity(
                existing,
                content: content,
                alertConfiguration: alertConfiguration
            )
            print("[LiveActivity][Message] Updated existing activity for conversation=\(conversationID)")
        } else {
            for activity in Activity<VoxiiMessageActivityAttributes>.activities {
                let currentContent = ActivityContent(
                    state: activity.content.state,
                    staleDate: Date(),
                    relevanceScore: 0.1
                )
                await activity.end(currentContent, dismissalPolicy: .immediate)
            }

            do {
                let activity = try Activity<VoxiiMessageActivityAttributes>.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
                if let alertConfiguration {
                    await activity.update(content, alertConfiguration: alertConfiguration)
                }
                print("[LiveActivity][Message] Started activity id=\(activity.id), conversation=\(conversationID)")
            } catch {
                print("[LiveActivity][Message] Failed to start: \(error.localizedDescription)")
                return
            }
        }

        scheduleMessageDismiss(for: conversationID)
    }

    func clearMessageActivities() async {
        guard #available(iOS 16.1, *) else {
            return
        }

        for task in messageDismissTasks.values {
            task.cancel()
        }
        messageDismissTasks.removeAll()

        for activity in Activity<VoxiiMessageActivityAttributes>.activities {
            let content = ActivityContent(
                state: activity.content.state,
                staleDate: Date(),
                relevanceScore: 0
            )
            await activity.end(content, dismissalPolicy: .immediate)
        }
    }

    func reportIncomingCall(
        _ payload: IncomingCallPayload,
        preferAlertPresentation: Bool = false
    ) async {
        await upsertCall(
            eventID: payload.id,
            callerName: payload.callerUsername,
            avatarText: payload.callerAvatar ?? payload.callerUsername,
            isVideo: payload.isVideoCall,
            phase: .incoming,
            statusText: localizedIncomingStatus(isVideo: payload.isVideoCall),
            connectedSince: nil,
            alertConfiguration: callAlertConfiguration(
                callerName: payload.callerUsername,
                isVideo: payload.isVideoCall,
                preferAlertPresentation: preferAlertPresentation
            )
        )
    }

    func reportOutgoingCall(eventID: String, peerName: String, avatarText: String?, isVideo: Bool) async {
        await upsertCall(
            eventID: eventID,
            callerName: peerName,
            avatarText: avatarText ?? peerName,
            isVideo: isVideo,
            phase: .calling,
            statusText: localizedOutgoingStatus(isVideo: isVideo),
            connectedSince: nil,
            alertConfiguration: nil
        )
    }

    func updateCall(
        eventID: String,
        peerName: String,
        avatarText: String?,
        isVideo: Bool,
        phase: VoxiiCallActivityAttributes.Phase,
        statusText: String,
        connectedSince: Date? = nil
    ) async {
        await upsertCall(
            eventID: eventID,
            callerName: peerName,
            avatarText: avatarText ?? peerName,
            isVideo: isVideo,
            phase: phase,
            statusText: statusText,
            connectedSince: connectedSince,
            alertConfiguration: nil
        )
    }

    func endCall(eventID: String, finalStatus: String? = nil, finalPhase: VoxiiCallActivityAttributes.Phase = .ended) async {
        guard #available(iOS 16.1, *) else {
            return
        }
        guard let activity = Activity<VoxiiCallActivityAttributes>.activities.first(where: { $0.attributes.eventID == eventID }) else {
            return
        }

        let state = VoxiiCallActivityAttributes.ContentState(
            phase: finalPhase,
            statusText: finalStatus ?? localizedEndedStatus(),
            connectedSince: activity.content.state.connectedSince,
            updatedAt: Date()
        )
        let content = ActivityContent(
            state: state,
            staleDate: Date(),
            relevanceScore: 0
        )
        await activity.end(content, dismissalPolicy: .immediate)
    }

    private func upsertCall(
        eventID: String,
        callerName: String,
        avatarText: String,
        isVideo: Bool,
        phase: VoxiiCallActivityAttributes.Phase,
        statusText: String,
        connectedSince: Date?,
        alertConfiguration: AlertConfiguration?
    ) async {
        guard #available(iOS 16.1, *), canPresentLiveActivities else {
            print("[LiveActivity][Call] Skipped: Live Activities are unavailable")
            return
        }

        let attributes = VoxiiCallActivityAttributes(
            eventID: eventID,
            callerName: callerName,
            avatarText: avatarText,
            callType: isVideo ? .video : .audio,
            deepLink: "voxii://call/\(eventID)"
        )
        let state = VoxiiCallActivityAttributes.ContentState(
            phase: phase,
            statusText: statusText,
            connectedSince: connectedSince,
            updatedAt: Date()
        )
        let content = ActivityContent(
            state: state,
            staleDate: connectedSince == nil ? Date().addingTimeInterval(240) : nil,
            relevanceScore: phase == .connected ? 1 : 0.95
        )

        if let existing = Activity<VoxiiCallActivityAttributes>.activities.first(where: { $0.attributes.eventID == eventID }) {
            if let alertConfiguration {
                await existing.update(content, alertConfiguration: alertConfiguration)
            } else {
                await existing.update(content)
            }
            print("[LiveActivity][Call] Updated existing activity for event=\(eventID), phase=\(phase.rawValue)")
            return
        }

        do {
            let activity = try Activity<VoxiiCallActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            if let alertConfiguration {
                await activity.update(content, alertConfiguration: alertConfiguration)
            }
            print("[LiveActivity][Call] Started activity id=\(activity.id), event=\(eventID), phase=\(phase.rawValue)")
        } catch {
            print("[LiveActivity][Call] Failed to start: \(error.localizedDescription)")
        }
    }

    private func updateMessageActivity(
        _ activity: Activity<VoxiiMessageActivityAttributes>,
        content: ActivityContent<VoxiiMessageActivityAttributes.ContentState>,
        alertConfiguration: AlertConfiguration?
    ) async {
        if let alertConfiguration {
            await activity.update(content, alertConfiguration: alertConfiguration)
        } else {
            await activity.update(content)
        }
    }

    private func scheduleMessageDismiss(for conversationID: String) {
        messageDismissTasks[conversationID]?.cancel()
        messageDismissTasks[conversationID] = Task { [conversationID] in
            try? await Task.sleep(nanoseconds: 90 * 1_000_000_000)
            guard !Task.isCancelled else {
                return
            }
            await endMessageActivity(conversationID: conversationID)
        }
    }

    private func endMessageActivity(conversationID: String) async {
        guard #available(iOS 16.1, *) else {
            return
        }
        messageDismissTasks[conversationID] = nil

        guard let activity = Activity<VoxiiMessageActivityAttributes>.activities.first(where: { $0.attributes.conversationID == conversationID }) else {
            return
        }

        let content = ActivityContent(
            state: activity.content.state,
            staleDate: Date(),
            relevanceScore: 0
        )
        await activity.end(content, dismissalPolicy: .immediate)
    }

    private func localizedMessageStatus() -> String {
        prefersRussianLanguage() ? "Новое сообщение" : "New message"
    }

    private func messageAlertConfiguration(
        title: String,
        body: String,
        preferAlertPresentation: Bool
    ) -> AlertConfiguration? {
        guard preferAlertPresentation else {
            return nil
        }
        return AlertConfiguration(
            title: LocalizedStringResource(String.LocalizationValue(title)),
            body: LocalizedStringResource(String.LocalizationValue(body)),
            sound: .default
        )
    }

    private func callAlertConfiguration(
        callerName: String,
        isVideo: Bool,
        preferAlertPresentation: Bool
    ) -> AlertConfiguration? {
        guard preferAlertPresentation else {
            return nil
        }
        let body: String
        if prefersRussianLanguage() {
            body = isVideo ? "Входящий видеозвонок" : "Входящий звонок"
        } else {
            body = isVideo ? "Incoming video call" : "Incoming call"
        }
        return AlertConfiguration(
            title: LocalizedStringResource(String.LocalizationValue(callerName)),
            body: LocalizedStringResource(String.LocalizationValue(body)),
            sound: .default
        )
    }

    private func localizedIncomingStatus(isVideo: Bool) -> String {
        if prefersRussianLanguage() {
            return isVideo ? "Входящий видеозвонок" : "Входящий звонок"
        }
        return isVideo ? "Incoming video call" : "Incoming call"
    }

    private func localizedOutgoingStatus(isVideo: Bool) -> String {
        if prefersRussianLanguage() {
            return isVideo ? "Исходящий видеозвонок" : "Исходящий звонок"
        }
        return isVideo ? "Outgoing video call" : "Outgoing call"
    }

    private func localizedEndedStatus() -> String {
        prefersRussianLanguage() ? "Звонок завершён" : "Call ended"
    }

    private func prefersRussianLanguage() -> Bool {
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: "voxii_language")?.lowercased() {
            return saved.hasPrefix("ru")
        }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return preferred.hasPrefix("ru")
    }
}
