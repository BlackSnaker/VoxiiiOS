//
//  VixiiApp.swift
//  Vixii
//
//  Created by Oleg on 04.03.2026.
//

import SwiftUI
import UIKit
import UserNotifications
import PushKit

extension Notification.Name {
    static let voxiiPushTokenDidUpdate = Notification.Name("voxiiPushTokenDidUpdate")
}

@MainActor
enum VoxiiPushNotifications {
    private static let defaults = UserDefaults.standard
    private static let apnsTokenKey = "voxii_apns_device_token"
    private static let voipTokenKey = "voxii_voip_device_token"
    private static let foregroundMessageNotificationKey = "voxiiForegroundMessageNotification"
    private static var isAPNsRegistrationDisabledForSession = false

    static var storedAPNSToken: String? {
        let token = defaults.string(forKey: apnsTokenKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (token?.isEmpty == false) ? token : nil
    }

    static var storedVoIPToken: String? {
        let token = defaults.string(forKey: voipTokenKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (token?.isEmpty == false) ? token : nil
    }

    static var supportsRemotePushRegistration: Bool {
        !isAPNsRegistrationDisabledForSession
    }

    static func requestAuthorizationAndRegisterIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        do {
            let settings = await center.notificationSettings()
            let authorizationGranted: Bool
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                authorizationGranted = true
            case .notDetermined:
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                guard granted else {
                    return
                }
                authorizationGranted = true
            case .denied:
                return
            @unknown default:
                return
            }

            guard authorizationGranted else {
                return
            }

            guard supportsRemotePushRegistration else {
                print("[Push] Skipping APNs registration for current session")
                return
            }

            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            print("[Push] Authorization request failed: \(error.localizedDescription)")
        }
    }

    static func saveDeviceToken(_ data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        guard !token.isEmpty else {
            return
        }
        isAPNsRegistrationDisabledForSession = false
        defaults.set(token, forKey: apnsTokenKey)
        NotificationCenter.default.post(
            name: .voxiiPushTokenDidUpdate,
            object: ["provider": "apns", "token": token]
        )
        print("[Push] APNs token updated")
    }

    static func disableAPNsRegistrationForCurrentSession() {
        isAPNsRegistrationDisabledForSession = true
        defaults.removeObject(forKey: apnsTokenKey)
    }

    static func saveVoIPToken(_ data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        guard !token.isEmpty else {
            return
        }
        defaults.set(token, forKey: voipTokenKey)
        NotificationCenter.default.post(
            name: .voxiiPushTokenDidUpdate,
            object: ["provider": "voip", "token": token]
        )
        print("[Push] VoIP token updated")
    }

    static func scheduleForegroundMessageNotification(messageID: String, title: String, body: String) {
        guard UIApplication.shared.applicationState != .active else {
            print("[Push][Message] Foreground notification suppressed because app is active")
            return
        }

        let trimmedID = messageID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            return
        }

        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBody.isEmpty else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = normalizedTitle.isEmpty ? "Voxii" : normalizedTitle
        content.body = normalizedBody
        content.sound = .default
        content.userInfo = [
            foregroundMessageNotificationKey: true,
            "messageId": trimmedID
        ]

        let request = UNNotificationRequest(
            identifier: "voxii-foreground-message-\(trimmedID)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.15, repeats: false)
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[Push][Message] Failed to schedule foreground notification: \(error.localizedDescription)")
            } else {
                print("[Push][Message] Foreground notification scheduled: id=\(trimmedID)")
            }
        }
    }
}

final class VoxiiAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, PKPushRegistryDelegate {
    private var voipRegistry: PKPushRegistry?
    private let syntheticMessageNotificationKey = "voxiiSyntheticMessageNotification"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        configureVoIPPushes()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        VoxiiPushNotifications.saveDeviceToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        let description = error.localizedDescription.lowercased()
        if description.contains("aps-environment") || description.contains("entitlement") {
            VoxiiPushNotifications.disableAPNsRegistrationForCurrentSession()
            print("[Push] APNs registration skipped: aps-environment entitlement is missing")
            return
        }
        print("[Push] Failed to register for remote notifications: \(error.localizedDescription)")
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        let requestID = notification.request.identifier
        if let payload = IncomingCallPayload.fromRemoteNotification(userInfo: userInfo) {
            VoxiiCallKitManager.shared.reportIncomingCall(payload)
            completionHandler([])
            return
        }
        if requestID.hasPrefix("voxii-foreground-message-")
            || (userInfo[syntheticMessageNotificationKey] as? Bool) == true
            || IncomingMessageNotificationPayload.fromRemoteNotification(userInfo: userInfo) != nil {
            completionHandler([])
            return
        }
        completionHandler([.banner, .list, .badge, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        let userInfo = response.notification.request.content.userInfo
        guard let payload = IncomingCallPayload.fromRemoteNotification(userInfo: userInfo) else {
            return
        }
        VoxiiCallKitManager.shared.receiveAnsweredCallPayload(payload)
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        if let payload = IncomingCallPayload.fromRemoteNotification(userInfo: userInfo) {
            print("[Push][Call] Remote call notification received: caller=\(payload.callerUsername)")
            VoxiiCallKitManager.shared.reportIncomingCall(payload)
            completionHandler(.newData)
            return
        }

        if let messagePayload = IncomingMessageNotificationPayload.fromRemoteNotification(userInfo: userInfo) {
            let hasVisibleAlert = remoteNotificationContainsVisibleAlert(userInfo: userInfo)
            print(
                "[Push][Message] Remote message notification received: id=\(messagePayload.id), hasAlert=\(hasVisibleAlert)"
            )
            if !hasVisibleAlert && application.applicationState != .active {
                scheduleSyntheticMessageNotification(messagePayload)
            }
            completionHandler(.newData)
            return
        }

        print("[Push] Remote notification received but not recognized")
        completionHandler(.noData)
    }

    private func configureVoIPPushes() {
        let registry = PKPushRegistry(queue: .main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        voipRegistry = registry
    }

    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else {
            return
        }
        VoxiiPushNotifications.saveVoIPToken(pushCredentials.token)
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) { }

    func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        defer { completion() }
        guard type == .voIP,
              let callPayload = IncomingCallPayload.fromRemoteNotification(userInfo: payload.dictionaryPayload) else {
            return
        }
        VoxiiCallKitManager.shared.reportIncomingCall(callPayload)
    }

    private func scheduleSyntheticMessageNotification(_ payload: IncomingMessageNotificationPayload) {
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        content.sound = .default
        content.userInfo = [
            syntheticMessageNotificationKey: true,
            "messageId": payload.id
        ]

        let request = UNNotificationRequest(
            identifier: "voxii-message-\(payload.id)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.15, repeats: false)
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[Push][Message] Failed to schedule local notification: \(error.localizedDescription)")
            } else {
                print("[Push][Message] Local fallback notification scheduled: id=\(payload.id)")
            }
        }
    }

    private func remoteNotificationContainsVisibleAlert(userInfo: [AnyHashable: Any]) -> Bool {
        let root = stringifyKeys(userInfo)
        if let aps = dictionary(from: root["aps"]) {
            if let alertText = firstNonEmptyString(aps["alert"]) {
                return !alertText.isEmpty
            }
            if let alert = dictionary(from: aps["alert"]),
               let preview = firstNonEmptyString(alert["title"], alert["body"]) {
                return !preview.isEmpty
            }
        }
        if let direct = firstNonEmptyString(root["title"], root["body"], root["alert"]) {
            return !direct.isEmpty
        }
        return false
    }

    private func stringifyKeys(_ value: [AnyHashable: Any]) -> [String: Any] {
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

    private func dictionary(from value: Any?) -> [String: Any]? {
        if let object = value as? [String: Any] {
            return object
        }
        if let object = value as? [AnyHashable: Any] {
            return stringifyKeys(object)
        }
        return nil
    }

    private func firstNonEmptyString(_ values: Any?...) -> String? {
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
}

@main
struct VixiiApp: App {
    @UIApplicationDelegateAdaptor(VoxiiAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
