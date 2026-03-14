import ActivityKit
import SwiftUI
import WidgetKit

struct VoxiiCallLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VoxiiCallActivityAttributes.self) { context in
            HStack(spacing: 12) {
                VoxiiLiveAvatar(
                    text: context.attributes.avatarText,
                    tint: callTint(for: context),
                    size: 46
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(context.attributes.callerName)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Text(context.state.statusText)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        callTrailingBadge(for: context)
                    }

                    HStack(spacing: 8) {
                        VoxiiGlassPill(
                            icon: context.attributes.callType == .video ? "video.fill" : "phone.fill",
                            text: callModeLabel(for: context),
                            tint: callTint(for: context),
                            style: .tinted
                        )

                        VoxiiGlassPill(
                            icon: compactCallStatusSymbol(for: context.state.phase),
                            text: callBottomLabel(for: context),
                            tint: .white,
                            style: .soft
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(callBackground(for: context))
            .widgetURL(URL(string: context.attributes.deepLink))
            .activityBackgroundTint(Color.black.opacity(0.88))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VoxiiLiveAvatar(
                        text: context.attributes.avatarText,
                        tint: callTint(for: context),
                        size: 44
                    )
                }

                DynamicIslandExpandedRegion(.trailing) {
                    callTrailingBadge(for: context)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 6) {
                        Text(context.attributes.callerName)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        VoxiiGlassPill(
                            icon: compactCallStatusSymbol(for: context.state.phase),
                            text: context.state.statusText,
                            tint: .white,
                            style: .soft
                        )
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        VoxiiGlassPill(
                            icon: context.attributes.callType == .video ? "video.fill" : "phone.fill",
                            text: callBottomLabel(for: context),
                            tint: callTint(for: context),
                            style: .tinted
                        )

                        Spacer(minLength: 0)

                        if let connectedSince = context.state.connectedSince, context.state.phase == .connected {
                            VoxiiTimerPill(date: connectedSince)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: context.attributes.callType == .video ? "video.fill" : "phone.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(callTint(for: context))
            } compactTrailing: {
                if let connectedSince = context.state.connectedSince, context.state.phase == .connected {
                    Text(connectedSince, style: .timer)
                        .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: compactCallStatusSymbol(for: context.state.phase))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            } minimal: {
                Image(systemName: context.attributes.callType == .video ? "video.fill" : "phone.fill")
                    .foregroundStyle(callTint(for: context))
            }
            .keylineTint(callTint(for: context))
            .widgetURL(URL(string: context.attributes.deepLink))
        }
    }

    private func callModeLabel(for context: ActivityViewContext<VoxiiCallActivityAttributes>) -> String {
        let isRussian = prefersRussianLanguage()
        if context.attributes.callType == .video {
            return isRussian ? "Видео" : "Video"
        }
        return isRussian ? "Аудио" : "Audio"
    }

    private func callTint(for context: ActivityViewContext<VoxiiCallActivityAttributes>) -> Color {
        switch context.state.phase {
        case .incoming:
            return Color(red: 0.36, green: 0.80, blue: 1.00)
        case .calling, .connecting:
            return Color(red: 0.47, green: 0.68, blue: 1.00)
        case .connected:
            return Color(red: 0.36, green: 0.96, blue: 0.71)
        case .ended, .missed:
            return Color(red: 1.00, green: 0.45, blue: 0.45)
        }
    }

    private func callBottomLabel(for context: ActivityViewContext<VoxiiCallActivityAttributes>) -> String {
        let isRussian = prefersRussianLanguage()
        switch context.state.phase {
        case .incoming:
            if isRussian {
                return context.attributes.callType == .video ? "Входящий видеозвонок" : "Входящий звонок"
            }
            return context.attributes.callType == .video ? "Incoming video call" : "Incoming call"
        case .calling:
            if isRussian {
                return context.attributes.callType == .video ? "Дозвон в Voxii" : "Звонок в Voxii"
            }
            return context.attributes.callType == .video ? "Dialing in Voxii" : "Calling in Voxii"
        case .connecting:
            return isRussian ? "Защищённое подключение" : "Connecting securely"
        case .connected:
            return isRussian ? "Нажмите, чтобы вернуться к звонку" : "Tap to return to call"
        case .ended:
            return isRussian ? "Звонок завершён" : "Call finished"
        case .missed:
            return isRussian ? "Пропущенный звонок" : "Missed call"
        }
    }

    @ViewBuilder
    private func callTrailingBadge(for context: ActivityViewContext<VoxiiCallActivityAttributes>) -> some View {
        if let connectedSince = context.state.connectedSince, context.state.phase == .connected {
            VoxiiTimerPill(date: connectedSince)
        } else {
            Image(systemName: compactCallStatusSymbol(for: context.state.phase))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(callTint(for: context))
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial.opacity(0.34))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                )
        }
    }

    private func compactCallStatusSymbol(for phase: VoxiiCallActivityAttributes.Phase) -> String {
        switch phase {
        case .incoming:
            return "phone.arrow.down.left.fill"
        case .calling:
            return "phone.arrow.up.right.fill"
        case .connecting:
            return "waveform"
        case .connected:
            return "phone.fill"
        case .ended, .missed:
            return "phone.down.fill"
        }
    }

    private func callBackground(for context: ActivityViewContext<VoxiiCallActivityAttributes>) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.06, blue: 0.11),
                    Color(red: 0.07, green: 0.09, blue: 0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    callTint(for: context).opacity(0.26),
                    .clear
                ],
                center: .topLeading,
                startRadius: 12,
                endRadius: 180
            )

            LinearGradient(
                colors: [
                    callTint(for: context).opacity(0.18),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.28))

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct VoxiiMessageLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VoxiiMessageActivityAttributes.self) { context in
            HStack(spacing: 12) {
                VoxiiLiveAvatar(
                    text: context.attributes.avatarText,
                    tint: messageTint,
                    size: 44
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(context.state.senderName)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Text(context.state.statusText)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        VStack(alignment: .trailing, spacing: 6) {
                            VoxiiCounterBadge(count: context.state.unreadCount, tint: messageTint)
                            VoxiiTimeBadge(date: context.state.receivedAt)
                        }
                    }

                    HStack(spacing: 8) {
                        VoxiiGlassPill(
                            icon: "message.fill",
                            text: context.state.statusText,
                            tint: messageTint,
                            style: .tinted
                        )

                        VoxiiGlassPill(
                            icon: "bell.fill",
                            text: unreadLabel(count: context.state.unreadCount),
                            tint: .white,
                            style: .soft
                        )
                    }

                    VoxiiPreviewBubble(
                        text: context.state.previewText,
                        tint: messageTint
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(messageBackground)
            .widgetURL(URL(string: context.attributes.deepLink))
            .activityBackgroundTint(Color.black.opacity(0.9))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VoxiiLiveAvatar(
                        text: context.attributes.avatarText,
                        tint: messageTint,
                        size: 44
                    )
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 6) {
                        VoxiiCounterBadge(count: context.state.unreadCount, tint: messageTint)
                        VoxiiTimeBadge(date: context.state.receivedAt)
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 6) {
                        Text(context.state.senderName)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        VoxiiGlassPill(
                            icon: "message.fill",
                            text: context.state.statusText,
                            tint: messageTint,
                            style: .tinted
                        )
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VoxiiPreviewBubble(
                        text: context.state.previewText,
                        tint: messageTint
                    )
                }
            } compactLeading: {
                Image(systemName: "message.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(messageTint)
            } compactTrailing: {
                VoxiiCompactCounter(count: context.state.unreadCount)
            } minimal: {
                Image(systemName: "message.fill")
                    .foregroundStyle(messageTint)
            }
            .keylineTint(messageTint)
            .widgetURL(URL(string: context.attributes.deepLink))
        }
    }

    private var messageTint: Color {
        Color(red: 0.44, green: 0.79, blue: 1.00)
    }

    private func unreadLabel(count: Int) -> String {
        let normalized = max(count, 1)
        if prefersRussianLanguage() {
            return normalized == 1 ? "1 новое" : "\(normalized) новых"
        }
        return normalized == 1 ? "1 new" : "\(normalized) new"
    }

    private var messageBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.06, blue: 0.11),
                    Color(red: 0.07, green: 0.09, blue: 0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    messageTint.opacity(0.28),
                    .clear
                ],
                center: .topLeading,
                startRadius: 14,
                endRadius: 180
            )

            LinearGradient(
                colors: [
                    messageTint.opacity(0.18),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.28))

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct VoxiiCounterBadge: View {
    let count: Int
    let tint: Color

    var body: some View {
        Text("\(max(count, 1))")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(minWidth: 30)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.34))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
            )
    }
}

private struct VoxiiCompactCounter: View {
    let count: Int

    var body: some View {
        Text("\(max(count, 1))")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(minWidth: 18)
    }
}

private struct VoxiiTimeBadge: View {
    let date: Date

    var body: some View {
        Text(date, style: .time)
            .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.26))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
    }
}

private enum VoxiiGlassPillStyle {
    case tinted
    case soft
}

private struct VoxiiGlassPill: View {
    let icon: String
    let text: String
    let tint: Color
    var style: VoxiiGlassPillStyle = .soft

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(style == .tinted ? .white : .white.opacity(0.9))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(background)
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .tinted:
            Capsule(style: .continuous)
                .fill(tint.opacity(0.28))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        case .soft:
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.24))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
    }
}

private struct VoxiiPreviewBubble: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "message.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tint.opacity(0.18))
                )

            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.26))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

private struct VoxiiTimerPill: View {
    let date: Date

    var body: some View {
        Text(date, style: .timer)
            .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.28))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
    }
}

private struct VoxiiLiveAvatar: View {
    let text: String
    let tint: Color
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            tint.opacity(0.96),
                            tint.opacity(0.52),
                            tint.opacity(0.18)
                        ],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: size
                    )
                )

            Circle()
                .fill(.ultraThinMaterial.opacity(0.24))
                .padding(1.7)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.28),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(size * 0.14)

            Text(initials(from: text))
                .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: tint.opacity(0.24), radius: 12, x: 0, y: 5)
    }

    private func initials(from value: String) -> String {
        let parts = value
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }

        if parts.count >= 2 {
            return (String(parts[0].prefix(1)) + String(parts[1].prefix(1))).uppercased()
        }

        if let first = parts.first {
            return String(first.prefix(2)).uppercased()
        }

        return "VX"
    }
}

private func prefersRussianLanguage() -> Bool {
    let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
    return preferred.hasPrefix("ru")
}
