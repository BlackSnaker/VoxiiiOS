import SwiftUI
import Combine
import UniformTypeIdentifiers
import AVFoundation
import WebKit

private func voxiiPrefersRussianLanguage() -> Bool {
    if let stored = UserDefaults.standard.string(forKey: "voxii_language")?.lowercased(), !stored.isEmpty {
        return stored == "ru"
    }
    let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
    return preferred.hasPrefix("ru")
}

private enum DMMessageTextPolicy {
    static let attachmentPlaceholder = "[voxii_attachment]"
    static let invisibleFallbackText = "\u{200B}"
    static let voiceFallbackLabel = "🎤 Voice message"
    private static let playableExtensions = Set(["m4a", "mp3", "wav", "aac", "ogg", "webm", "flac", "mp4"])

    static func visibleText(_ rawText: String, hasAttachment: Bool) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == attachmentPlaceholder {
            return ""
        }

        if rawText == invisibleFallbackText {
            return ""
        }

        if trimmed == voiceFallbackLabel {
            return hasAttachment ? "" : voiceFallbackLabel
        }

        if voiceUploadReference(from: rawText) != nil {
            return ""
        }

        guard hasAttachment else {
            return rawText
        }

        if trimmed.isEmpty {
            return ""
        }

        return rawText
    }

    static func visibleOptionalText(_ rawText: String?, hasAttachment: Bool) -> String? {
        guard let rawText else {
            return nil
        }
        return visibleText(rawText, hasAttachment: hasAttachment)
    }

    static func voiceUploadReference(from rawText: String) -> String? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let resolved = URL(string: trimmed) ?? URL(string: trimmed, relativeTo: URL(string: "https://voxii.local"))
        guard let resolved else {
            return nil
        }

        let lowerPath = resolved.path.lowercased()
        guard lowerPath.contains("/uploads/") else {
            return nil
        }

        let filename = resolved.lastPathComponent.lowercased()
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        guard playableExtensions.contains(ext) else {
            return nil
        }

        if filename.contains("voice") || filename.contains("audio") || lowerPath.contains("voice") {
            return trimmed
        }

        return nil
    }

    static func voiceUploadURL(from rawText: String) -> URL? {
        guard let reference = voiceUploadReference(from: rawText) else {
            return nil
        }
        guard let url = URL(string: reference), url.scheme != nil else {
            return nil
        }
        return url
    }
}

private struct ComposerEmojiCategory: Identifiable, Hashable {
    let id: String
    let icon: String
    let titleKey: String
    let emojis: [String]
}

private enum ComposerEmojiCatalog {
    static let categories: [ComposerEmojiCategory] = [
        .init(
            id: "smileys",
            icon: "😀",
            titleKey: "chat.emojiCategory.smileys",
            emojis: ["😀", "😃", "😄", "😁", "😆", "😅", "🤣", "😂", "🙂", "🙃", "😉", "😊", "🥰", "😍", "😘", "😎", "🤩", "🥳", "😇", "🤗", "🤔", "😴", "🤤", "🤯", "😤", "😭", "😡", "🥺", "😮", "😏", "🙄", "🤐", "🤠", "👻", "💀", "🤖"]
        ),
        .init(
            id: "people",
            icon: "👋",
            titleKey: "chat.emojiCategory.people",
            emojis: ["👋", "🤚", "🖐️", "✋", "🫶", "👌", "🤌", "🤏", "✌️", "🤞", "🤟", "🤘", "👍", "👎", "👏", "🙌", "🙏", "💪", "🫡", "👀", "🫶", "🤝", "💅", "✍️", "🕺", "💃", "🧑‍💻", "👨‍💻", "👩‍💻", "🧠", "👑", "🎅"]
        ),
        .init(
            id: "animals",
            icon: "🐶",
            titleKey: "chat.emojiCategory.animals",
            emojis: ["🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐮", "🐷", "🐸", "🐵", "🐔", "🐧", "🐦", "🦄", "🐝", "🦋", "🐢", "🐬", "🐙", "🌸", "🌹", "🌺", "🌻", "🌈", "⭐", "🔥", "🌙"]
        ),
        .init(
            id: "food",
            icon: "🍔",
            titleKey: "chat.emojiCategory.food",
            emojis: ["🍏", "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐", "🍒", "🥝", "🍍", "🥥", "🥑", "🍅", "🥕", "🌽", "🍔", "🍟", "🍕", "🌭", "🌮", "🌯", "🥪", "🍣", "🍜", "🍝", "🍩", "🍪", "🎂", "☕"]
        ),
        .init(
            id: "activities",
            icon: "⚽",
            titleKey: "chat.emojiCategory.activities",
            emojis: ["⚽", "🏀", "🏈", "⚾", "🎾", "🏐", "🏓", "🥊", "🥋", "⛷️", "🏂", "🏋️", "🤸", "🏄", "🏊", "🚴", "🏆", "🥇", "🎯", "🎮", "🎲", "🎳", "🎹", "🎸", "🎤", "🎧", "🎬", "🎨", "🎭", "🎉", "🎊", "✨"]
        ),
        .init(
            id: "symbols",
            icon: "❤️",
            titleKey: "chat.emojiCategory.symbols",
            emojis: ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔", "❣️", "💕", "💞", "💓", "💗", "💖", "💘", "💝", "💯", "✅", "❌", "⭕", "⚠️", "🚫", "‼️", "⁉️", "💬", "🗯️", "♻️", "🔔", "⭐", "✨"]
        )
    ]

    static let defaultCategoryID = categories.first?.id ?? "smileys"
}

struct ChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var appearance: VoxiiAppearance

    let peer: APIUser

    @State private var messages: [DirectMessage] = []
    @State private var messageText = ""
    @State private var isEmojiPickerPresented = false
    @State private var selectedEmojiCategoryID = ComposerEmojiCatalog.defaultCategoryID
    @State private var replyToMessage: DirectMessage?
    @State private var editingMessage: DirectMessage?
    @State private var messageIdForDelete: Int?

    @State private var pendingAttachment: PendingAttachment?
    @State private var isFileImporterPresented = false
    @State private var isTranscribing = false
    @State private var voiceRecorder: AVAudioRecorder?
    @State private var voiceRecordingURL: URL?
    @State private var isRecordingVoice = false
    @State private var isVideoCallPresented = false

    @State private var isSending = false
    @State private var isSyncing = false
    @State private var errorMessage: String?
    @State private var isDeleteDialogPresented = false
    @State private var localAttachmentByMessageID: [Int: APIFileAttachment] = [:]
    @State private var didCompleteInitialMessageLoad = false

    @FocusState private var isComposerFocused: Bool

    private let refreshTimer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            VoxiiBackground()

            VStack(spacing: 12) {
                header
                messagesArea
                composer
            }
            .padding(12)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadMessages()
        }
        .onReceive(refreshTimer) { _ in
            guard scenePhase == .active,
                  !isVideoCallPresented,
                  !isRecordingVoice,
                  !isSending else {
                return
            }
            Task { await loadMessages() }
        }
        .onDisappear {
            finishVoiceRecording(save: false)
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false,
            onCompletion: handleFileSelection
        )
        .confirmationDialog(appearance.t("chat.deletePrompt"), isPresented: $isDeleteDialogPresented, titleVisibility: .visible) {
            Button(appearance.t("common.delete"), role: .destructive) {
                guard let messageID = messageIdForDelete else {
                    return
                }
                Task { await deleteMessage(messageID) }
            }
            Button(appearance.t("common.cancel"), role: .cancel) {
                messageIdForDelete = nil
            }
        }
        .alert(appearance.t("common.error"), isPresented: errorBinding) {
            Button(appearance.t("common.ok"), role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? appearance.t("common.unknownError"))
        }
        .fullScreenCover(isPresented: $isVideoCallPresented) {
            VideoCallView(
                config: .init(
                    baseServerURL: session.serverURL,
                    token: session.token ?? "",
                    selfUser: session.currentUser,
                    peer: peer,
                    callType: "video",
                    mode: .outgoing
                )
            ) {
                isVideoCallPresented = false
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
            }
            .buttonStyle(VoxiiRoundButtonStyle(diameter: 40, variant: .neutral))

            VoxiiAvatarView(
                text: peer.avatar ?? peer.username,
                isOnline: peer.status?.lowercased() == "online",
                size: 44
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(peer.username)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(VoxiiTheme.text)

                peerStatusBadge
            }

            Spacer()

            Button {
                isVideoCallPresented = true
            } label: {
                Image(systemName: "video.fill")
                    .font(.system(size: 14, weight: .bold))
            }
            .buttonStyle(VoxiiRoundButtonStyle(diameter: 40, variant: .accent))
            .disabled(session.token == nil || isSending || isRecordingVoice)

            Button {
                Task { await loadMessages() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .bold))
            }
            .buttonStyle(VoxiiRoundButtonStyle(diameter: 40, variant: .neutral))
            .disabled(isSyncing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(chatSurface(cornerRadius: 24, tint: VoxiiTheme.accentBlue.opacity(0.08)))
    }

    private var messagesArea: some View {
        ZStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubbleView(
                                message: message,
                                isOutgoing: message.senderID == session.currentUser?.id,
                                currentUsername: session.currentUser?.username,
                                fileURL: message.file.flatMap { session.absoluteURL(for: $0.url) },
                                onReply: {
                                    replyToMessage = message
                                    editingMessage = nil
                                },
                                onEdit: {
                                    editingMessage = message
                                    messageText = DMMessageTextPolicy.visibleText(
                                        message.content,
                                        hasAttachment: message.file != nil
                                    )
                                    replyToMessage = nil
                                },
                                onDelete: {
                                    messageIdForDelete = message.id
                                    isDeleteDialogPresented = true
                                },
                                onReactionTap: { reaction in
                                    Task { await toggleReaction(for: message.id, reaction: reaction) }
                                },
                                onReactionPick: { emoji in
                                    Task { await addReaction(to: message.id, emoji: emoji) }
                                },
                                onUseTranscription: { text in
                                    appendTranscribedText(text)
                                },
                                onOpenFile: { url in
                                    openURL(url)
                                }
                            )
                            .id(message.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 14)
                }
                .onChange(of: messages.count) { _, _ in
                    guard let lastID = messages.last?.id else {
                        return
                    }
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }

            if messages.isEmpty && !isSyncing {
                emptyMessagesState
                    .padding(.horizontal, 28)
            }
        }
        .background(chatSurface(cornerRadius: 28, tint: Color.white.opacity(0.02)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .simultaneousGesture(
            TapGesture().onEnded {
                guard isEmojiPickerPresented else {
                    return
                }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    isEmojiPickerPresented = false
                }
            }
        )
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let editingMessage {
                actionBanner(
                    icon: "square.and.pencil",
                    title: appearance.t("chat.editing"),
                    detail: previewText(for: editingMessage),
                    onCancel: {
                        self.editingMessage = nil
                        messageText = ""
                    }
                )
            } else if let replyToMessage {
                actionBanner(
                    icon: "arrowshape.turn.up.left.fill",
                    title: appearance.tf("chat.replyingTo", replyToMessage.username ?? appearance.t("common.unknown")),
                    detail: previewText(for: replyToMessage),
                    onCancel: {
                        self.replyToMessage = nil
                    }
                )
            }

            if let pendingAttachment {
                attachmentBanner(pendingAttachment)
            }

            if isRecordingVoice {
                voiceRecordingBanner
            }

            if isEmojiPickerPresented && !isRecordingVoice {
                emojiPickerBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .bottom, spacing: 10) {
                HStack(alignment: .bottom, spacing: 10) {
                    Button {
                        isEmojiPickerPresented = false
                        isFileImporterPresented = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .buttonStyle(
                        VoxiiRoundButtonStyle(
                            diameter: 34,
                            variant: .neutral,
                            foregroundColor: VoxiiTheme.accentLight
                        )
                    )
                    .disabled(isSending || isRecordingVoice || editingMessage != nil)

                    TextField(composerPlaceholder, text: $messageText, axis: .vertical)
                        .lineLimit(1...4)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(VoxiiTheme.text)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled(false)
                        .focused($isComposerFocused)
                        .disabled(isRecordingVoice)

                    Button {
                        toggleEmojiPicker()
                    } label: {
                        Image(systemName: isEmojiPickerPresented ? "keyboard.chevron.compact.down.fill" : "face.smiling.fill")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .buttonStyle(
                        VoxiiRoundButtonStyle(
                            diameter: 34,
                            variant: isEmojiPickerPresented ? .accent : .neutral,
                            foregroundColor: isEmojiPickerPresented ? .white : VoxiiTheme.accentLight
                        )
                    )
                    .accessibilityLabel(appearance.t("chat.emojiPicker"))
                    .disabled(isSending || isRecordingVoice)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: VoxiiTheme.controlHeightRegular)
                .background(chatSurface(cornerRadius: 26, tint: VoxiiTheme.accent.opacity(0.08)))

                Button {
                    handleComposerActionTap()
                } label: {
                    if isSending {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: composerActionIcon)
                            .font(.system(size: 17, weight: .bold))
                    }
                }
                .buttonStyle(VoxiiRoundButtonStyle(diameter: 48, variant: composerActionVariant))
                .disabled(composerActionDisabled)
            }
        }
        .padding(.horizontal, 2)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isEmojiPickerPresented)
    }

    private var composerPlaceholder: String {
        editingMessage == nil ? appearance.t("chat.messagePlaceholder") : appearance.t("chat.updatePlaceholder")
    }

    private var canStartVoiceFromAction: Bool {
        editingMessage == nil && pendingAttachment == nil
    }

    private var composerActionIcon: String {
        if isRecordingVoice {
            return "stop.fill"
        }
        if canSend {
            return editingMessage == nil ? "paperplane.fill" : "checkmark"
        }
        return "mic.fill"
    }

    private var composerActionVariant: VoxiiButtonVariant {
        if isRecordingVoice {
            return .danger
        }
        return .accent
    }

    private var composerActionDisabled: Bool {
        if isSending {
            return true
        }
        if isRecordingVoice || canSend {
            return false
        }
        return !canStartVoiceFromAction
    }

    private var selectedEmojiCategory: ComposerEmojiCategory {
        ComposerEmojiCatalog.categories.first(where: { $0.id == selectedEmojiCategoryID }) ?? ComposerEmojiCatalog.categories[0]
    }

    private var emojiGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 28, maximum: 40), spacing: 8), count: 8)
    }

    private var emojiPickerBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "face.smiling.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(VoxiiTheme.accentLight)

                    Text(appearance.t("chat.emojiPicker"))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(VoxiiTheme.text)
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        isEmojiPickerPresented = false
                    }
                    isComposerFocused = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(
                    VoxiiRoundButtonStyle(
                        diameter: 28,
                        variant: .neutral,
                        foregroundColor: VoxiiTheme.accentLight
                    )
                )
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ComposerEmojiCatalog.categories) { category in
                        Button {
                            selectedEmojiCategoryID = category.id
                        } label: {
                            HStack(spacing: 6) {
                                Text(category.icon)
                                    .font(.system(size: 16))

                                Text(appearance.t(category.titleKey))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(selectedEmojiCategoryID == category.id ? Color.white : VoxiiTheme.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(emojiCategoryBackground(isSelected: selectedEmojiCategoryID == category.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }

            Text(appearance.t(selectedEmojiCategory.titleKey))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(VoxiiTheme.muted)
                .padding(.horizontal, 2)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: emojiGridColumns, spacing: 8) {
                    ForEach(selectedEmojiCategory.emojis, id: \.self) { emoji in
                        Button {
                            insertEmoji(emoji)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 24))
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .padding(.vertical, 3)
                                .background(emojiOptionBackground)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 2)
            }
            .frame(height: 156)
        }
        .padding(12)
        .background(chatBannerSurface(cornerRadius: 24, tint: VoxiiTheme.accent.opacity(0.1)))
    }

    private func emojiCategoryBackground(isSelected: Bool) -> some View {
        Capsule(style: .continuous)
            .fill(isSelected ? AnyShapeStyle(VoxiiTheme.accentGradient) : AnyShapeStyle(Color.white.opacity(0.05)))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.14 : 0.08), lineWidth: 0.9)
            )
    }

    private var emojiOptionBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
            )
    }

    private func toggleEmojiPicker() {
        guard !isSending, !isRecordingVoice else {
            return
        }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            isEmojiPickerPresented.toggle()
        }

        if isEmojiPickerPresented {
            isComposerFocused = true
        }
    }

    private func insertEmoji(_ emoji: String) {
        messageText += emoji
        errorMessage = nil
        isComposerFocused = true
    }

    private func handleComposerActionTap() {
        guard !isSending else {
            return
        }

        if isRecordingVoice {
            isEmojiPickerPresented = false
            toggleVoiceRecording()
            return
        }

        if canSend {
            isEmojiPickerPresented = false
            Task { await sendOrUpdate() }
            return
        }

        guard canStartVoiceFromAction else {
            return
        }
        isEmojiPickerPresented = false
        toggleVoiceRecording()
    }

    private func appendTranscribedText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        if messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messageText = trimmed
        } else {
            messageText += "\n\(trimmed)"
        }

        errorMessage = nil
        isEmojiPickerPresented = false
        isComposerFocused = true
    }

    private var canSend: Bool {
        guard !isRecordingVoice else {
            return false
        }

        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        if editingMessage != nil {
            return !trimmed.isEmpty
        }
        return !trimmed.isEmpty || pendingAttachment != nil
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

    private func actionBanner(icon: String, title: String, detail: String, onCancel: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(VoxiiTheme.accentLight)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.08))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(VoxiiTheme.accentLight)
                Text(detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .foregroundStyle(VoxiiTheme.muted)
            }

            Spacer()

            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(VoxiiGradientButtonStyle(isCompact: true, variant: .neutral))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(chatBannerSurface(cornerRadius: 18, tint: VoxiiTheme.accent.opacity(0.08)))
    }

    private func attachmentBanner(_ attachment: PendingAttachment) -> some View {
        HStack(spacing: 10) {
            Image(systemName: attachment.isAudio ? "waveform.circle.fill" : "doc.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(VoxiiTheme.accentLight)

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(VoxiiTheme.text)
                Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.data.count), countStyle: .file))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(VoxiiTheme.muted)
            }

            Spacer()

            if attachment.isAudio {
                Button {
                    Task { await transcribePendingAudio() }
                } label: {
                    if isTranscribing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(appearance.t("chat.transcribe"))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                }
                .buttonStyle(VoxiiGradientButtonStyle(isCompact: true, variant: .neutral))
                .disabled(isTranscribing || isSending)
            }

            Button {
                pendingAttachment = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(VoxiiGradientButtonStyle(isCompact: true, variant: .neutral))
            .disabled(isSending)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(chatBannerSurface(cornerRadius: 18, tint: VoxiiTheme.accent.opacity(0.06)))
    }

    private var voiceRecordingBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "record.circle.fill")
                .foregroundStyle(.red)

            Text(appearance.t("chat.recording"))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(VoxiiTheme.text)

            Spacer()

            Button(appearance.t("common.cancel")) {
                finishVoiceRecording(save: false)
            }
            .buttonStyle(VoxiiGradientButtonStyle(isCompact: true, variant: .neutral))
            .disabled(isSending)

            Button(appearance.t("chat.stop")) {
                finishVoiceRecording(save: true)
            }
            .buttonStyle(VoxiiGradientButtonStyle(isCompact: true))
            .disabled(isSending)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(chatBannerSurface(cornerRadius: 18, tint: VoxiiTheme.danger.opacity(0.08)))
    }

    private var peerStatusBadge: some View {
        let isOnline = peer.status?.lowercased() == "online"

        return HStack(spacing: 6) {
            Circle()
                .fill(isOnline ? VoxiiTheme.online : VoxiiTheme.mutedSecondary)
                .frame(width: 7, height: 7)

            Text(appearance.statusLabel(peer.status))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(isOnline ? VoxiiTheme.online : VoxiiTheme.muted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        )
    }

    private var emptyMessagesState: some View {
        VStack(spacing: 12) {
            VoxiiAvatarView(
                text: peer.avatar ?? peer.username,
                isOnline: peer.status?.lowercased() == "online",
                size: 62
            )

            Text(appearance.t("chat.emptyTitle"))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(VoxiiTheme.text)

            Text(appearance.tf("chat.emptySubtitle", peer.username))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(VoxiiTheme.muted)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(chatBannerSurface(cornerRadius: 24, tint: VoxiiTheme.accentBlue.opacity(0.05)))
    }

    private func chatSurface(cornerRadius: CGFloat, tint: Color) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                tint,
                                VoxiiTheme.glassStrong.opacity(0.72),
                                Color.black.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 6)
    }

    private func chatBannerSurface(cornerRadius: CGFloat, tint: Color) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        tint,
                        VoxiiTheme.glass.opacity(0.82)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    private func loadMessages() async {
        guard !isSyncing else {
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let previousMessageIDs = Set(messages.map(\.id))
            let fetchedMessages = try await session.fetchMessages(with: peer.id)
            var attachmentCache = localAttachmentByMessageID
            let mergedMessages = fetchedMessages.map { message in
                if let file = message.file {
                    attachmentCache[message.id] = file
                    return message
                }

                guard let cachedFile = attachmentCache[message.id] else {
                    return message
                }

                return messageWithOverriddenFile(message, file: cachedFile)
            }

            let existingIDs = Set(mergedMessages.map(\.id))
            attachmentCache = attachmentCache.filter { existingIDs.contains($0.key) }
            localAttachmentByMessageID = attachmentCache

            let shouldPlayIncomingSound = didCompleteInitialMessageLoad && mergedMessages.contains { message in
                !previousMessageIDs.contains(message.id) && message.senderID != session.currentUser?.id
            }

            if mergedMessages != messages {
                messages = mergedMessages
                if shouldPlayIncomingSound {
                    VoxiiMessageSoundPlayer.shared.playIncoming()
                }
            }
            didCompleteInitialMessageLoad = true
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func sendOrUpdate() async {
        isSending = true
        defer { isSending = false }

        let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            if let editingMessage {
                guard !trimmedText.isEmpty else {
                    throw APIClientError.server(appearance.t("chat.messageEmpty"))
                }

                _ = try await session.updateMessage(messageID: editingMessage.id, text: trimmedText)
            } else {
                var uploadedFileId: Int?
                var uploadedAttachment: APIFileAttachment?
                if let pendingAttachment {
                    let uploaded = try await uploadPendingAttachment(pendingAttachment)
                    uploadedFileId = uploaded.id
                    uploadedAttachment = uploaded
                    print("[ChatView][Send] Attachment uploaded with id=\(uploaded.id), type=\(uploaded.type ?? "unknown"), url=\(uploaded.url)")
                }

                let fileIdDebug = uploadedFileId.map { String($0) } ?? "nil"
                let replyIdDebug = replyToMessage.map { String($0.id) } ?? "nil"
                let isVoiceAttachment = pendingAttachment?.isAudio == true
                let requestFileId: Int? = uploadedFileId
                let requestFileIdDebug = requestFileId.map { String($0) } ?? "nil"
                let preparedText: String = {
                    if isVoiceAttachment, trimmedText.isEmpty {
                        return DMMessageTextPolicy.invisibleFallbackText
                    }
                    return trimmedText
                }()

                if preparedText.isEmpty && uploadedFileId == nil {
                    throw APIClientError.server(appearance.t("chat.messageEmpty"))
                }
                var sentMessage: DirectMessage

                if isVoiceAttachment, let uploadedAttachment {
                    let voiceSocketText = trimmedText.isEmpty
                        ? DMMessageTextPolicy.invisibleFallbackText
                        : trimmedText
                    print("[ChatView][Send] Sending voice DM over socket textLength=\(voiceSocketText.count) fileId=\(fileIdDebug) replyToId=\(replyIdDebug)")
                    sentMessage = try await session.sendVoiceMessageOverSocket(
                        to: peer.id,
                        text: voiceSocketText,
                        file: uploadedAttachment,
                        replyToId: replyToMessage?.id,
                        isVoiceMessage: true
                    )
                } else {
                    print("[ChatView][Send] Sending DM textLength=\(preparedText.count) fileId=\(requestFileIdDebug) uploadFileId=\(fileIdDebug) replyToId=\(replyIdDebug)")
                    sentMessage = try await session.sendMessage(
                        to: peer.id,
                        text: preparedText,
                        fileId: requestFileId,
                        file: uploadedAttachment,
                        replyToId: replyToMessage?.id,
                        isVoiceMessage: nil
                    )
                }

                if uploadedFileId != nil && sentMessage.file == nil {
                    print("[ChatView][Send] Warning: DM saved without attached file in response (messageId=\(sentMessage.id))")
                    if let uploadedAttachment {
                        localAttachmentByMessageID[sentMessage.id] = uploadedAttachment
                        sentMessage = messageWithOverriddenFile(sentMessage, file: uploadedAttachment)
                    }
                } else if let attachedFile = sentMessage.file {
                    localAttachmentByMessageID[sentMessage.id] = attachedFile
                }

                upsertMessage(sentMessage)
                VoxiiMessageSoundPlayer.shared.playSend()
            }

            messageText = ""
            replyToMessage = nil
            editingMessage = nil
            pendingAttachment = nil
            isEmojiPickerPresented = false
            errorMessage = nil
            await loadMessages()
        } catch {
            print("[ChatView][Send] Failed: \(error.localizedDescription)")
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func deleteMessage(_ messageID: Int) async {
        do {
            try await session.deleteMessage(messageID: messageID)
            messages.removeAll { $0.id == messageID }
            messageIdForDelete = nil
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func uploadPendingAttachment(_ attachment: PendingAttachment) async throws -> APIFileAttachment {
        if !attachment.isAudio {
            return try await session.uploadFile(
                to: peer.id,
                fileData: attachment.data,
                filename: attachment.filename,
                mimeType: attachment.mimeType,
                isVoiceMessage: false
            )
        }

        let baseName: String = {
            if let dotIndex = attachment.filename.lastIndex(of: ".") {
                return String(attachment.filename[..<dotIndex])
            }
            return attachment.filename
        }()

        let attempts: [(filename: String, mimeType: String)] = [
            (attachment.filename, attachment.mimeType), // primary
            ("\(baseName).m4a", "audio/mp4"),          // canonical MIME for AAC in MP4 container
            ("\(baseName).m4a", "audio/m4a")           // backend compatibility fallback
        ]

        var lastError: Error?
        for attempt in attempts {
            do {
                print("[ChatView][VoiceUpload] Attempting upload as \(attempt.filename) (\(attempt.mimeType))")
                return try await session.uploadFile(
                    to: peer.id,
                    fileData: attachment.data,
                    filename: attempt.filename,
                    mimeType: attempt.mimeType,
                    isVoiceMessage: true
                )
            } catch {
                print("[ChatView][VoiceUpload] Upload failed for \(attempt.filename) (\(attempt.mimeType)): \(error.localizedDescription)")
                lastError = error
            }
        }

        throw lastError ?? APIClientError.server(appearance.t("chat.uploadVoiceFailed"))
    }

    private func addReaction(to messageID: Int, emoji: String) async {
        do {
            let response = try await session.addReaction(messageID: messageID, emoji: emoji)
            applyReactionUpdate(messageID: response.messageId, reactions: response.reactions)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func toggleReaction(for messageID: Int, reaction: ReactionSummary) async {
        guard let currentUsername = session.currentUser?.username else {
            return
        }

        let alreadyMine = reaction.users?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .contains(currentUsername.lowercased()) ?? false

        do {
            let response: MessageReactionsResponse
            if alreadyMine {
                response = try await session.removeReaction(messageID: messageID, emoji: reaction.emoji)
            } else {
                response = try await session.addReaction(messageID: messageID, emoji: reaction.emoji)
            }

            applyReactionUpdate(messageID: response.messageId, reactions: response.reactions)
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func applyReactionUpdate(messageID: Int, reactions: [ReactionSummary]) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }

        let old = messages[index]
        messages[index] = DirectMessage(
            id: old.id,
            content: old.content,
            senderID: old.senderID,
            receiverID: old.receiverID,
            username: old.username,
            avatar: old.avatar,
            createdAt: old.createdAt,
            reactions: reactions,
            file: old.file,
            edited: old.edited,
            originalContent: old.originalContent,
            replyTo: old.replyTo
        )
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else {
                return
            }
            loadAttachment(url)
        }
    }

    private func loadAttachment(_ url: URL) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            if data.count > 10 * 1024 * 1024 {
                throw APIClientError.server(appearance.t("chat.fileTooLarge"))
            }

            let mimeType = UTType.mimeType(for: url.pathExtension.lowercased())
            pendingAttachment = PendingAttachment(
                filename: url.lastPathComponent,
                mimeType: mimeType,
                data: data
            )
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func toggleVoiceRecording() {
        if isRecordingVoice {
            finishVoiceRecording(save: true)
        } else {
            Task {
                await startVoiceRecording()
            }
        }
    }

    private func startVoiceRecording() async {
        guard !isRecordingVoice else {
            return
        }

        guard editingMessage == nil else {
            errorMessage = appearance.t("chat.voiceWhileEditing")
            return
        }

        guard pendingAttachment == nil else {
            errorMessage = appearance.t("chat.removeAttachmentFirst")
            return
        }

        let granted = await requestMicrophonePermission()
        guard granted else {
            errorMessage = appearance.t("chat.microphoneDenied")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)

            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("voice-\(UUID().uuidString)")
                .appendingPathExtension("m4a")

            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.prepareToRecord()

            guard recorder.record() else {
                throw APIClientError.server(appearance.t("chat.voiceStartFailed"))
            }

            voiceRecorder = recorder
            voiceRecordingURL = fileURL
            isRecordingVoice = true
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            deactivateRecordingAudioSession()
        }
    }

    private func finishVoiceRecording(save: Bool) {
        guard let recorder = voiceRecorder else {
            isRecordingVoice = false
            if !save {
                cleanupVoiceRecordingFile()
            }
            return
        }

        let duration = recorder.currentTime
        recorder.stop()
        voiceRecorder = nil
        isRecordingVoice = false
        deactivateRecordingAudioSession()

        if !save {
            cleanupVoiceRecordingFile()
            return
        }

        guard duration >= 0.25 else {
            cleanupVoiceRecordingFile()
            errorMessage = appearance.t("chat.voiceTooShort")
            return
        }

        guard let voiceRecordingURL else {
            errorMessage = appearance.t("chat.voiceFileMissing")
            return
        }

        do {
            let data = try Data(contentsOf: voiceRecordingURL)
            if data.count > 10 * 1024 * 1024 {
                throw APIClientError.server(appearance.t("chat.voiceTooLarge"))
            }

            let filename = "voice_message_\(Int(Date().timeIntervalSince1970)).m4a"
            // Use canonical MIME for AAC in M4A to improve browser playback.
            let mimeType = "audio/mp4"
            pendingAttachment = PendingAttachment(filename: filename, mimeType: mimeType, data: data)
            errorMessage = nil
            cleanupVoiceRecordingFile()
        } catch {
            cleanupVoiceRecordingFile()
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func cleanupVoiceRecordingFile() {
        if let voiceRecordingURL {
            try? FileManager.default.removeItem(at: voiceRecordingURL)
        }
        voiceRecordingURL = nil
    }

    private func deactivateRecordingAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func transcribePendingAudio() async {
        guard let pendingAttachment, pendingAttachment.isAudio else {
            return
        }

        isTranscribing = true
        defer { isTranscribing = false }

        do {
            let result = try await session.transcribeAudio(
                fileData: pendingAttachment.data,
                filename: pendingAttachment.filename,
                mimeType: pendingAttachment.mimeType
            )

            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw APIClientError.server(appearance.t("chat.noSpeechDetected"))
            }

            if messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messageText = text
            } else {
                messageText += "\n\(text)"
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func previewText(for message: DirectMessage) -> String {
        let visibleText = DMMessageTextPolicy.visibleText(
            message.content,
            hasAttachment: message.file != nil
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        if !visibleText.isEmpty {
            return visibleText
        }

        if let file = message.file {
            return appearance.tf("chat.attachment", file.filename)
        }

        if DMMessageTextPolicy.voiceUploadReference(from: message.content) != nil {
            return appearance.t("chat.voiceMessage")
        }

        return appearance.t("chat.noText")
    }

    private func messageWithOverriddenFile(_ message: DirectMessage, file: APIFileAttachment?) -> DirectMessage {
        DirectMessage(
            id: message.id,
            content: message.content,
            senderID: message.senderID,
            receiverID: message.receiverID,
            username: message.username,
            avatar: message.avatar,
            createdAt: message.createdAt,
            reactions: message.reactions,
            file: file,
            edited: message.edited,
            originalContent: message.originalContent,
            replyTo: message.replyTo
        )
    }

    private func messageWithOverriddenContent(_ message: DirectMessage, content: String) -> DirectMessage {
        DirectMessage(
            id: message.id,
            content: content,
            senderID: message.senderID,
            receiverID: message.receiverID,
            username: message.username,
            avatar: message.avatar,
            createdAt: message.createdAt,
            reactions: message.reactions,
            file: message.file,
            edited: message.edited,
            originalContent: message.originalContent,
            replyTo: message.replyTo
        )
    }

    private func upsertMessage(_ message: DirectMessage) {
        if let existingIndex = messages.firstIndex(where: { $0.id == message.id }) {
            messages[existingIndex] = message
            return
        }

        messages.append(message)
        messages.sort { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id < rhs.id
            }
            return lhs.createdAt < rhs.createdAt
        }
    }
}

private struct PendingAttachment {
    let filename: String
    let mimeType: String
    let data: Data

    var isAudio: Bool {
        mimeType.hasPrefix("audio/")
    }
}

private struct MessageBubbleView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var appearance: VoxiiAppearance

    let message: DirectMessage
    let isOutgoing: Bool
    let currentUsername: String?
    let fileURL: URL?
    let onReply: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onReactionTap: (ReactionSummary) -> Void
    let onReactionPick: (String) -> Void
    let onUseTranscription: (String) -> Void
    let onOpenFile: (URL) -> Void

    private let reactionPalette = ["👍", "❤️", "😂", "🔥", "👏", "😮", "😢", "👀"]
    private var visibleMessageContent: String {
        DMMessageTextPolicy.visibleText(
            message.content,
            hasAttachment: message.file != nil
        )
    }
    private var fallbackVoiceURL: URL? {
        guard message.file == nil else {
            return nil
        }
        guard let voiceReference = DMMessageTextPolicy.voiceUploadReference(from: message.content) else {
            return nil
        }
        return session.absoluteURL(for: voiceReference) ?? URL(string: voiceReference)
    }

    var body: some View {
        HStack(alignment: .bottom) {
            if isOutgoing {
                Spacer(minLength: 40)
            }

            VStack(alignment: .leading, spacing: 5) {
                header

                if let reply = message.replyTo {
                    replyBlock(reply)
                }

                if !visibleMessageContent.isEmpty {
                    messageTextBlock(visibleMessageContent)
                }

                if let file = message.file {
                    fileBlock(file)
                } else if let fallbackVoiceURL {
                    fallbackVoiceBlock(fallbackVoiceURL)
                }

                if appearance.linkPreviewEnabled,
                   let urlString = firstURL(in: visibleMessageContent),
                   !appearance.isPreviewHidden(messageID: message.id, urlString: urlString) {
                    LinkPreviewCard(messageID: message.id, urlString: urlString)
                        .environmentObject(session)
                        .environmentObject(appearance)
                }

                reactionSection
                actionSection
            }
            .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(bubbleBackground)
            .overlay(
                bubbleShape
                    .stroke(bubbleStrokeStyle, lineWidth: 1)
            )
            .overlay(
                bubbleShape
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.4)
                    .padding(1)
            )
            .shadow(color: bubbleShadowColor, radius: 9, x: 0, y: 6)

            if !isOutgoing {
                Spacer(minLength: 40)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 6) {
            if !isOutgoing {
                senderChip
            }

            Spacer(minLength: 0)

            if message.edited {
                metadataChip(appearance.t("chat.edited"))
            }

            metadataChip(MessageDate.shortTime(message.createdAt))
        }
    }

    private func replyBlock(_ reply: ReplyPreview) -> some View {
        let visibleReplyText = DMMessageTextPolicy.visibleOptionalText(
            reply.text,
            hasAttachment: reply.file != nil
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let replyVoiceURL = DMMessageTextPolicy.voiceUploadReference(from: reply.text ?? "")

        return HStack(alignment: .top, spacing: 7) {
            RoundedRectangle(cornerRadius: 99, style: .continuous)
                .fill(isOutgoing ? Color.white.opacity(0.92) : VoxiiTheme.accentLight)
                .frame(width: 2.5)

            VStack(alignment: .leading, spacing: 1.5) {
                Text(appearance.tf("chat.replyAuthor", reply.author ?? appearance.t("common.unknown")))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(isOutgoing ? Color.white.opacity(0.94) : VoxiiTheme.accentLight)

                if let text = visibleReplyText, !text.isEmpty {
                    Text(text)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(isOutgoing ? Color.white.opacity(0.82) : VoxiiTheme.muted)
                        .lineLimit(1)
                } else if let file = reply.file {
                    Text(appearance.tf("chat.attachmentInline", file.filename))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(isOutgoing ? Color.white.opacity(0.82) : VoxiiTheme.muted)
                        .lineLimit(1)
                } else if replyVoiceURL != nil {
                    Text(appearance.t("chat.voiceInline"))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(isOutgoing ? Color.white.opacity(0.82) : VoxiiTheme.muted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(inlinePanelBackground(cornerRadius: 10))
    }

    private func fileBlock(_ file: APIFileAttachment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if isAudioAttachment(file), let fileURL {
                VoiceMessagePlayerView(
                    url: fileURL,
                    isOutgoing: isOutgoing,
                    onUseTranscription: onUseTranscription
                )
            } else {
                HStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(isOutgoing ? 0.14 : 0.08))
                        Image(systemName: iconForFile(file))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isOutgoing ? Color.white.opacity(0.94) : VoxiiTheme.accentLight)
                    }
                    .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.filename)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(isOutgoing ? .white : VoxiiTheme.text)
                            .lineLimit(1)

                        if let size = file.size {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(isOutgoing ? Color.white.opacity(0.78) : VoxiiTheme.muted)
                        }
                    }

                    Spacer()

                    if let fileURL {
                        Button {
                            onOpenFile(fileURL)
                        } label: {
                            Image(systemName: "arrow.up.forward")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isOutgoing ? Color.white.opacity(0.94) : VoxiiTheme.accentLight)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(
                            MessageBubbleActionIconStyle(
                                backgroundTint: Color.white.opacity(isOutgoing ? 0.14 : 0.08),
                                strokeTint: Color.white.opacity(isOutgoing ? 0.18 : 0.1)
                            )
                        )
                        .accessibilityLabel(appearance.t("common.open"))
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(inlinePanelBackground(cornerRadius: 11))
    }

    private func fallbackVoiceBlock(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            VoiceMessagePlayerView(
                url: url,
                isOutgoing: isOutgoing,
                onUseTranscription: onUseTranscription
            )
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(inlinePanelBackground(cornerRadius: 11))
    }

    private var reactionSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(message.reactions) { reaction in
                    Button {
                        onReactionTap(reaction)
                    } label: {
                        HStack(spacing: 4) {
                            Text(reaction.emoji)
                            Text("\(reaction.count)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(isOutgoing ? .white : VoxiiTheme.text)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(
                            Capsule()
                                .fill(reactedByCurrentUser(reaction) ? VoxiiTheme.accent.opacity(0.28) : Color.white.opacity(isOutgoing ? 0.12 : 0.05))
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(isOutgoing ? 0.2 : 0.1), lineWidth: 0.8)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }

                Menu {
                    ForEach(reactionPalette, id: \.self) { emoji in
                        Button(emoji) {
                            onReactionPick(emoji)
                        }
                    }
                } label: {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isOutgoing ? .white : VoxiiTheme.accent)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(isOutgoing ? 0.14 : 0.08))
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(isOutgoing ? 0.18 : 0.1), lineWidth: 0.8)
                                )
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionSection: some View {
        HStack(spacing: 7) {
            actionIconButton(
                systemImage: "arrowshape.turn.up.left.fill",
                accessibilityLabel: appearance.t("common.reply"),
                tint: isOutgoing ? Color.white.opacity(0.94) : VoxiiTheme.accentLight,
                backgroundTint: isOutgoing ? Color.white.opacity(0.1) : Color.white.opacity(0.05),
                strokeTint: Color.white.opacity(isOutgoing ? 0.14 : 0.08),
                action: onReply
            )

            if isOutgoing {
                actionIconButton(
                    systemImage: "square.and.pencil",
                    accessibilityLabel: appearance.t("common.edit"),
                    tint: Color.white.opacity(0.94),
                    backgroundTint: Color.white.opacity(0.1),
                    strokeTint: Color.white.opacity(0.14),
                    action: onEdit
                )

                actionIconButton(
                    systemImage: "trash.fill",
                    accessibilityLabel: appearance.t("common.delete"),
                    tint: Color(hex: "#FFB3B3") ?? VoxiiTheme.danger,
                    backgroundTint: VoxiiTheme.danger.opacity(0.18),
                    strokeTint: VoxiiTheme.danger.opacity(0.34),
                    action: onDelete
                )
            }
        }
        .padding(.top, 2)
        .padding(.horizontal, 4.5)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(isOutgoing ? 0.06 : 0.035))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(isOutgoing ? 0.1 : 0.06), lineWidth: 0.8)
        )
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func actionIconButton(
        systemImage: String,
        accessibilityLabel: String,
        tint: Color,
        backgroundTint: Color,
        strokeTint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(MessageBubbleActionIconStyle(backgroundTint: backgroundTint, strokeTint: strokeTint))
        .accessibilityLabel(accessibilityLabel)
    }

    private func reactedByCurrentUser(_ reaction: ReactionSummary) -> Bool {
        guard let currentUsername else {
            return false
        }

        return reaction.users?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .contains(currentUsername.lowercased()) ?? false
    }

    private func iconForFile(_ file: APIFileAttachment) -> String {
        let type = file.type?.lowercased() ?? ""
        if type.hasPrefix("image/") {
            return "photo"
        }
        if type.hasPrefix("audio/") {
            return "waveform"
        }
        if type.hasPrefix("video/") {
            return "film"
        }
        if file.filename.lowercased().hasSuffix(".pdf") {
            return "doc.richtext"
        }
        return "doc"
    }

    private func isAudioAttachment(_ file: APIFileAttachment) -> Bool {
        let type = file.type?.lowercased() ?? ""
        if type.hasPrefix("audio/") {
            return true
        }

        let extensionValue = URL(fileURLWithPath: file.filename).pathExtension.lowercased()
        if let detectedType = UTType(filenameExtension: extensionValue),
           detectedType.conforms(to: .audio) {
            return true
        }

        let lowerName = file.filename.lowercased()
        if type.hasPrefix("video/"),
           extensionValue == "mp4",
           (lowerName.contains("voice") || lowerName.contains("audio")) {
            return true
        }

        return ["m4a", "mp3", "wav", "aac", "ogg", "webm", "flac"].contains(extensionValue)
    }

    private func firstURL(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }

        let range = NSRange(location: 0, length: (text as NSString).length)
        return detector.firstMatch(in: text, options: [], range: range)?.url?.absoluteString
    }

    private var bubbleMaxWidth: CGFloat {
        286
    }

    private var bubbleCornerRadius: CGFloat {
        VoxiiTheme.radiusM + 4
    }

    private var bubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: bubbleCornerRadius,
                bottomLeading: isOutgoing ? bubbleCornerRadius : 10,
                bottomTrailing: isOutgoing ? 10 : bubbleCornerRadius,
                topTrailing: bubbleCornerRadius
            ),
            style: .continuous
        )
    }

    private var bubbleBackground: some View {
        ZStack {
            bubbleShape
                .fill(
                    isOutgoing
                    ? AnyShapeStyle(Color.black.opacity(0.08))
                    : AnyShapeStyle(Color.black.opacity(0.18))
                )

            bubbleShape
                .fill(bubbleFillStyle)

            bubbleShape
                .fill(bubbleAccentWash)

            bubbleShape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isOutgoing ? 0.025 : 0.015),
                            .clear,
                            Color.black.opacity(isOutgoing ? 0.12 : 0.18)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            bubbleShape
                .fill(bubbleGlossStyle)
                .blendMode(.screen)
        }
    }

    private var bubbleFillStyle: AnyShapeStyle {
        if isOutgoing {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        VoxiiTheme.accentLight.opacity(0.44),
                        VoxiiTheme.accent.opacity(0.68),
                        VoxiiTheme.accentBlue.opacity(0.6),
                        VoxiiTheme.accent.opacity(0.64)
                    ],
                    startPoint: .topTrailing,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.08),
                    VoxiiTheme.glassStrong.opacity(0.96),
                    VoxiiTheme.glass.opacity(0.86),
                    Color.black.opacity(0.28)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var bubbleAccentWash: RadialGradient {
        RadialGradient(
            colors: [
                isOutgoing ? Color.white.opacity(0.055) : VoxiiTheme.accentBlue.opacity(0.025),
                .clear
            ],
            center: isOutgoing ? .topTrailing : .topLeading,
            startRadius: 4,
            endRadius: 120
        )
    }

    private var bubbleGlossStyle: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(isOutgoing ? 0.09 : 0.04),
                Color.white.opacity(isOutgoing ? 0.03 : 0.01),
                .clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var bubbleStrokeStyle: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(isOutgoing ? 0.12 : 0.08),
                Color.white.opacity(isOutgoing ? 0.05 : 0.025)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var bubbleShadowColor: Color {
        (isOutgoing ? VoxiiTheme.accentBlue : .black).opacity(isOutgoing ? 0.18 : 0.13)
    }

    private func inlinePanelBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.black.opacity(isOutgoing ? 0.12 : 0.18))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isOutgoing ? 0.05 : 0.025),
                                (isOutgoing ? VoxiiTheme.accentLight.opacity(0.045) : VoxiiTheme.accent.opacity(0.025)),
                                Color.black.opacity(0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.04), Color.white.opacity(0.01), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.screen)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(isOutgoing ? 0.1 : 0.06), lineWidth: 0.8)
            )
    }

    private func messageTextBlock(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .medium, design: .rounded))
            .lineSpacing(2.6)
            .foregroundStyle(isOutgoing ? .white : VoxiiTheme.text)
            .textSelection(.enabled)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(textPanelBackground(cornerRadius: 13))
    }

    private func textPanelBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                isOutgoing
                ? AnyShapeStyle(Color.black.opacity(0.12))
                : AnyShapeStyle(Color.black.opacity(0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isOutgoing ? 0.04 : 0.02),
                                (isOutgoing ? VoxiiTheme.accentLight.opacity(0.04) : VoxiiTheme.accent.opacity(0.02)),
                                Color.black.opacity(0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.04), Color.white.opacity(0.01), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.screen)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(isOutgoing ? 0.08 : 0.05), lineWidth: 0.8)
            )
    }

    private var senderChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(VoxiiTheme.accentLight)
                .frame(width: 5, height: 5)

            Text(message.username ?? appearance.t("common.unknown"))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(VoxiiTheme.accentLight)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.18))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.8)
        )
    }

    private func metadataChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(isOutgoing ? 0.14 : 0.18))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(isOutgoing ? 0.08 : 0.05), lineWidth: 0.8)
            )
            .foregroundStyle(isOutgoing ? Color.white.opacity(0.8) : VoxiiTheme.muted)
    }
}

private struct MessageBubbleActionIconStyle: ButtonStyle {
    let backgroundTint: Color
    let strokeTint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(backgroundTint)
            )
            .overlay(
                Circle()
                    .stroke(strokeTint, lineWidth: 0.8)
            )
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .shadow(
                color: Color.black.opacity(configuration.isPressed ? 0.08 : 0.14),
                radius: configuration.isPressed ? 3 : 6,
                x: 0,
                y: configuration.isPressed ? 2 : 4
            )
            .contentShape(Circle())
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

private struct VoiceMessagePlayerView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var appearance: VoxiiAppearance

    let url: URL
    let isOutgoing: Bool
    let onUseTranscription: (String) -> Void

    @StateObject private var player: VoiceMessagePlayerModel
    @State private var isEditingProgress = false
    @State private var draftProgress = 0.0
    @State private var isTranscribing = false
    @State private var transcriptionText: String?
    @State private var transcriptionErrorText: String?

    init(url: URL, isOutgoing: Bool, onUseTranscription: @escaping (String) -> Void) {
        self.url = url
        self.isOutgoing = isOutgoing
        self.onUseTranscription = onUseTranscription
        _player = StateObject(wrappedValue: VoiceMessagePlayerModel(url: url))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    player.togglePlayback()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isOutgoing ? VoxiiTheme.accent : .white)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(isOutgoing ? AnyShapeStyle(Color.white) : AnyShapeStyle(VoxiiTheme.accentGradient))
                        )
                }
                .buttonStyle(.plain)
                .disabled(player.isLoading)

                VStack(alignment: .leading, spacing: 1) {
                    Text(appearance.t("chat.voiceMessage"))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(isOutgoing ? .white : VoxiiTheme.text)
                        .lineLimit(1)

                    Text("\(currentTimeText) / \(player.durationText)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(isOutgoing ? Color.white.opacity(0.78) : VoxiiTheme.muted)
                }

                Spacer()

                if player.isLoading {
                    ProgressView()
                        .tint(isOutgoing ? .white : VoxiiTheme.accent)
                        .scaleEffect(0.82)
                }
            }

            Slider(
                value: Binding(
                    get: { isEditingProgress ? draftProgress : player.progress },
                    set: { newValue in
                        draftProgress = newValue
                        if isEditingProgress {
                            player.previewProgress(newValue)
                        }
                    }
                ),
                in: 0...1,
                onEditingChanged: { isEditing in
                    isEditingProgress = isEditing
                    if isEditing {
                        draftProgress = player.progress
                    } else {
                        player.seek(to: draftProgress)
                    }
                }
            )
            .tint(isOutgoing ? .white : VoxiiTheme.accent)

            transcriptionSection

            if let errorText = player.errorText {
                Text(errorText)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.red.opacity(0.92))
            }
        }
        .onAppear {
            player.prepareIfNeeded()
        }
        .onDisappear {
            player.pause()
        }
    }

    private var currentTimeText: String {
        if isEditingProgress {
            return VoiceMessagePlayerModel.format(seconds: draftProgress * max(player.durationSeconds, 0))
        }
        return player.currentTimeText
    }

    @ViewBuilder
    private var transcriptionSection: some View {
        if let transcriptionText {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label {
                        Text(appearance.t("chat.transcription"))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    } icon: {
                        Image(systemName: "text.bubble.fill")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(isOutgoing ? Color.white.opacity(0.92) : VoxiiTheme.accentLight)

                    Spacer()

                    Button {
                        onUseTranscription(transcriptionText)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.down.left")
                                .font(.system(size: 10, weight: .bold))
                            Text(appearance.t("chat.useText"))
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(isOutgoing ? VoxiiTheme.accent : .white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(transcriptionActionBackground)
                    }
                    .buttonStyle(.plain)
                }

                Text(transcriptionText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineSpacing(2)
                    .foregroundStyle(isOutgoing ? Color.white.opacity(0.9) : VoxiiTheme.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(transcriptionCardBackground)
        } else {
            Button {
                Task { await transcribeVoiceMessage() }
            } label: {
                HStack(spacing: 8) {
                    if isTranscribing {
                        ProgressView()
                            .tint(isOutgoing ? .white : VoxiiTheme.accent)
                            .scaleEffect(0.82)
                    } else {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 12, weight: .bold))
                    }

                    Text(isTranscribing ? appearance.t("chat.transcribing") : appearance.t("chat.transcribe"))
                        .font(.system(size: 11, weight: .bold, design: .rounded))

                    Spacer()
                }
                .foregroundStyle(isOutgoing ? Color.white.opacity(0.92) : VoxiiTheme.accentLight)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(transcriptionPromptBackground)
            }
            .buttonStyle(.plain)
            .disabled(isTranscribing)
        }

        if let transcriptionErrorText {
            Text(transcriptionErrorText)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.red.opacity(0.92))
        }
    }

    private var transcriptionPromptBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(isOutgoing ? 0.08 : 0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(isOutgoing ? 0.1 : 0.08), lineWidth: 0.8)
            )
    }

    private var transcriptionCardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.black.opacity(isOutgoing ? 0.14 : 0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isOutgoing ? 0.04 : 0.02),
                                (isOutgoing ? VoxiiTheme.accentLight.opacity(0.04) : VoxiiTheme.accent.opacity(0.025)),
                                Color.black.opacity(0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(isOutgoing ? 0.1 : 0.06), lineWidth: 0.8)
            )
    }

    private var transcriptionActionBackground: some View {
        Capsule(style: .continuous)
            .fill(isOutgoing ? AnyShapeStyle(Color.white) : AnyShapeStyle(VoxiiTheme.accentGradient))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(isOutgoing ? 0.18 : 0.08), lineWidth: 0.8)
            )
    }

    private func transcribeVoiceMessage() async {
        guard !isTranscribing else {
            return
        }

        isTranscribing = true
        transcriptionErrorText = nil
        defer { isTranscribing = false }

        do {
            let payload = try await loadAudioPayload()
            let result = try await session.transcribeAudio(
                fileData: payload.data,
                filename: payload.filename,
                mimeType: payload.mimeType
            )

            let normalized = normalizedTranscription(result.text)
            guard !normalized.isEmpty else {
                throw APIClientError.server(appearance.t("chat.noSpeechDetected"))
            }

            transcriptionText = normalized
        } catch {
            transcriptionErrorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadAudioPayload() async throws -> (data: Data, filename: String, mimeType: String) {
        if url.isFileURL {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else {
                throw APIClientError.invalidUploadData
            }
            return (data, url.lastPathComponent, inferredMimeType(for: url))
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard !data.isEmpty else {
            throw APIClientError.invalidUploadData
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw APIClientError.server("HTTP \(httpResponse.statusCode)")
        }

        let filename = response.suggestedFilename ?? url.lastPathComponent
        let mimeType = response.mimeType ?? inferredMimeType(for: url)
        return (data, filename, mimeType)
    }

    private func inferredMimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m4a", "mp4":
            return "audio/mp4"
        case "mp3":
            return "audio/mpeg"
        case "wav":
            return "audio/wav"
        case "aac":
            return "audio/aac"
        case "ogg":
            return "audio/ogg"
        case "webm":
            return "audio/webm"
        case "flac":
            return "audio/flac"
        default:
            return "audio/m4a"
        }
    }

    private func normalizedTranscription(_ rawText: String) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()
        if normalized.isEmpty || normalized == "(no speech detected)" || normalized == "no speech detected" {
            return ""
        }
        return trimmed
    }
}

private final class VoiceMessagePlayerModel: ObservableObject {
    @Published private(set) var isLoading = true
    @Published private(set) var isPlaying = false
    @Published private(set) var progress = 0.0
    @Published private(set) var durationText = "0:00"
    @Published private(set) var currentTimeText = "0:00"
    @Published private(set) var durationSeconds = 0.0
    @Published var errorText: String?

    private let url: URL
    private let playerID = UUID()
    private var player: AVPlayer?
    private var statusObserver: NSKeyValueObservation?
    private var itemEndObserver: NSObjectProtocol?
    private var externalStopObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var shouldResumeAfterSeek = false

    init(url: URL) {
        self.url = url
    }

    deinit {
        cleanup()
    }

    func prepareIfNeeded() {
        guard player == nil else {
            return
        }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player

        statusObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            guard let self else {
                return
            }
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    self.isLoading = false
                    self.errorText = nil
                    self.updateDuration(from: item.duration)
                case .failed:
                    self.isLoading = false
                    self.errorText = item.error?.localizedDescription ?? Self.localizedPlaybackError()
                default:
                    self.isLoading = true
                }
            }
        }

        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else {
                return
            }
            self.isPlaying = false
            self.progress = 1
            self.currentTimeText = self.durationText
        }

        externalStopObserver = NotificationCenter.default.addObserver(
            forName: .voxiiStopVoicePlayback,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else {
                return
            }
            guard let sourceID = notification.object as? UUID, sourceID != self.playerID else {
                return
            }
            self.pause()
        }

        let interval = CMTime(seconds: 0.2, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.handlePlaybackTime(time)
        }
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        prepareIfNeeded()
        guard let player else {
            return
        }

        if progress >= 0.999 {
            seek(to: 0)
        }

        NotificationCenter.default.post(name: .voxiiStopVoicePlayback, object: playerID)
        configureAudioSessionForPlayback()

        player.play()
        isPlaying = true
    }

    func pause() {
        guard let player else {
            return
        }
        player.pause()
        isPlaying = false
    }

    func seek(to progress: Double) {
        guard let player, durationSeconds > 0 else {
            return
        }

        let target = max(0, min(1, progress)) * durationSeconds
        let targetTime = CMTime(seconds: target, preferredTimescale: 600)
        let resume = shouldResumeAfterSeek || isPlaying
        player.pause()
        isPlaying = false

        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self else {
                return
            }
            Task { @MainActor in
                self.currentTimeText = Self.format(seconds: target)
                self.progress = max(0, min(1, progress))
                if resume {
                    self.player?.play()
                    self.isPlaying = true
                }
                self.shouldResumeAfterSeek = false
            }
        }
    }

    func previewProgress(_ progress: Double) {
        guard durationSeconds > 0 else {
            return
        }
        shouldResumeAfterSeek = isPlaying
        if isPlaying {
            pause()
        }
        let seconds = max(0, min(1, progress)) * durationSeconds
        currentTimeText = Self.format(seconds: seconds)
    }

    private func handlePlaybackTime(_ time: CMTime) {
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite, seconds >= 0 else {
            return
        }

        currentTimeText = Self.format(seconds: seconds)
        if durationSeconds > 0 {
            progress = min(1, max(0, seconds / durationSeconds))
        }
    }

    private func updateDuration(from time: CMTime) {
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite, seconds > 0 else {
            durationSeconds = 0
            durationText = "0:00"
            return
        }
        durationSeconds = seconds
        durationText = Self.format(seconds: seconds)
    }

    private func configureAudioSessionForPlayback() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothHFP])
        try? session.setActive(true)
    }

    private func cleanup() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        if let itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
            self.itemEndObserver = nil
        }

        if let externalStopObserver {
            NotificationCenter.default.removeObserver(externalStopObserver)
            self.externalStopObserver = nil
        }

        statusObserver?.invalidate()
        statusObserver = nil

        player?.pause()
        player = nil
    }

    static func format(seconds: Double) -> String {
        guard seconds.isFinite, !seconds.isNaN else {
            return "0:00"
        }

        let total = Int(seconds.rounded(.towardZero))
        let minutes = total / 60
        let remaining = total % 60
        return "\(minutes):" + String(format: "%02d", remaining)
    }

    private static func localizedPlaybackError() -> String {
        if voxiiPrefersRussianLanguage() {
            return "Не удалось воспроизвести голосовое сообщение."
        }
        return "Cannot play this voice message."
    }
}

private extension Notification.Name {
    static let voxiiStopVoicePlayback = Notification.Name("voxii.stopVoicePlayback")
}

private struct LinkPreviewCard: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var appearance: VoxiiAppearance
    @Environment(\.openURL) private var openURL

    let messageID: Int
    let urlString: String

    @State private var metadata: LinkPreviewMetadata?

    var body: some View {
        Button {
            if let url = URL(string: urlString) {
                openURL(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(previewTitle)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(VoxiiTheme.text)
                    .lineLimit(2)

                if let description = previewDescription {
                    Text(description)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(VoxiiTheme.muted)
                        .lineLimit(2)
                }

                Text(previewSite)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(VoxiiTheme.accentLight)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(VoxiiTheme.glass)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(VoxiiTheme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(appearance.t("chat.hidePreview")) {
                appearance.hidePreview(messageID: messageID, urlString: urlString)
            }
        }
        .task(id: urlString) {
            await loadPreview()
        }
    }

    private func loadPreview() async {
        guard appearance.linkPreviewEnabled,
              !appearance.isPreviewHidden(messageID: messageID, urlString: urlString) else {
            return
        }
        do {
            metadata = try await session.fetchLinkPreview(url: urlString)
        } catch {
            // Ignore preview errors and show fallback URL.
        }
    }

    private var previewTitle: String {
        normalized(metadata.flatMap { $0.title }) ?? urlString
    }

    private var previewDescription: String? {
        normalized(metadata.flatMap { $0.description })
    }

    private var previewSite: String {
        normalized(metadata.flatMap { $0.siteName }) ?? URL(string: urlString)?.host ?? appearance.t("common.link")
    }

    private func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

private enum MessageDate {
    private static let isoWithFractionalSeconds: ISO8601DateFormatter = {
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

    private static let displayTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    static func shortTime(_ value: String) -> String {
        guard let date = parse(value) else {
            return value
        }
        return displayTime.string(from: date)
    }

    private static func parse(_ value: String) -> Date? {
        if let date = isoWithFractionalSeconds.date(from: value) {
            return date
        }
        if let date = iso.date(from: value) {
            return date
        }
        if let date = sqlite.date(from: value) {
            return date
        }
        return nil
    }
}

enum VideoCallMode: String {
    case outgoing
    case incoming
}

struct VideoCallConfig {
    let baseServerURL: String
    let token: String
    let selfUser: APIUser?
    let peer: APIUser
    let callType: String
    let mode: VideoCallMode
    let initialIncomingSocketId: String?
    let initialIncomingUserId: Int?
    let initialIncomingUsername: String?
    let initialIncomingAvatar: String?
    let autoAcceptIncoming: Bool

    init(
        baseServerURL: String,
        token: String,
        selfUser: APIUser?,
        peer: APIUser,
        callType: String,
        mode: VideoCallMode,
        initialIncomingSocketId: String? = nil,
        initialIncomingUserId: Int? = nil,
        initialIncomingUsername: String? = nil,
        initialIncomingAvatar: String? = nil,
        autoAcceptIncoming: Bool = false
    ) {
        self.baseServerURL = baseServerURL
        self.token = token
        self.selfUser = selfUser
        self.peer = peer
        self.callType = callType
        self.mode = mode
        self.initialIncomingSocketId = initialIncomingSocketId
        self.initialIncomingUserId = initialIncomingUserId
        self.initialIncomingUsername = initialIncomingUsername
        self.initialIncomingAvatar = initialIncomingAvatar
        self.autoAcceptIncoming = autoAcceptIncoming
    }
}

private enum VideoCallState: Equatable {
    case connecting
    case calling
    case incoming
    case connected
    case ended
}

@MainActor
private final class VideoCallController: ObservableObject {
    @Published var statusText = VideoCallController.localizedConnectingShort()
    @Published var state: VideoCallState = .connecting
    @Published var isAudioEnabled = true
    @Published var isVideoEnabled = true
    @Published var hasRemoteVideo = false
    @Published var incomingCallerName: String?
    @Published var errorMessage: String?

    weak var webView: WKWebView?

    func attach(webView: WKWebView) {
        self.webView = webView
    }

    func toggleAudio() {
        run("window.voxii && window.voxii.toggleAudio();")
    }

    func toggleVideo() {
        run("window.voxii && window.voxii.toggleVideo();")
    }

    func endCall() {
        run("window.voxii && window.voxii.endCall();")
    }

    func acceptIncoming() {
        run("window.voxii && window.voxii.acceptIncoming();")
    }

    func rejectIncoming() {
        run("window.voxii && window.voxii.rejectIncoming();")
    }

    func handle(payload: [String: Any]) {
        guard let type = payload["type"] as? String else {
            return
        }

        switch type {
        case "status":
            if let text = payload["text"] as? String, !text.isEmpty {
                statusText = text
            }
        case "state":
            guard let raw = payload["state"] as? String else {
                return
            }
            switch raw {
            case "connecting":
                state = .connecting
            case "calling":
                state = .calling
            case "incoming":
                state = .incoming
            case "connected":
                state = .connected
            case "ended":
                state = .ended
            default:
                break
            }
        case "audio":
            isAudioEnabled = payload["enabled"] as? Bool ?? true
        case "video":
            isVideoEnabled = payload["enabled"] as? Bool ?? true
        case "remote":
            hasRemoteVideo = payload["hasRemote"] as? Bool ?? false
        case "incoming":
            incomingCallerName = payload["caller"] as? String
            state = .incoming
        case "error":
            errorMessage = payload["message"] as? String ?? Self.localizedVideoError()
        case "ended":
            state = .ended
        default:
            break
        }
    }

    private func run(_ script: String) {
        webView?.evaluateJavaScript(script)
    }

    private static func localizedConnectingShort() -> String {
        voxiiPrefersRussianLanguage() ? "Подключение..." : "Connecting..."
    }

    private static func localizedVideoError() -> String {
        voxiiPrefersRussianLanguage() ? "Ошибка видеозвонка." : "Video call error."
    }
}

@MainActor
final class VoxiiMessageSoundPlayer: NSObject, @preconcurrency AVAudioPlayerDelegate {
    static let shared = VoxiiMessageSoundPlayer()

    private enum SoundKind {
        case send
        case incoming

        var debugName: String {
            switch self {
            case .send:
                return "send"
            case .incoming:
                return "incoming"
            }
        }
    }

    private var activePlayers: [AVAudioPlayer] = []

    private override init() {}

    func playSend() {
        play(.send)
    }

    func playIncoming() {
        play(.incoming)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        activePlayers.removeAll { $0 === player }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        activePlayers.removeAll { $0 === player }
    }

    private func play(_ kind: SoundKind) {
        let preset = VoxiiSoundPreferences.messageSoundPreset
        guard preset != .off else {
            return
        }

        do {
            let url = try soundFileURL(for: kind, preset: preset)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.volume = kind == .send ? 0.22 : 0.3
            player.prepareToPlay()

            guard player.play() else {
                return
            }

            activePlayers.append(player)
        } catch {
            print("[ChatView][Sound] Failed to play \(kind.debugName): \(error.localizedDescription)")
        }
    }

    private func soundFileURL(for kind: SoundKind, preset: VoxiiMessageSoundPreset) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
        let fileURL = directory.appendingPathComponent(Self.fileName(for: kind, preset: preset))

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let wavData = makeMessageToneWAV(for: kind, preset: preset, sampleRate: 22_050)
            try wavData.write(to: fileURL, options: .atomic)
        }

        return fileURL
    }

    private static func fileName(for kind: SoundKind, preset: VoxiiMessageSoundPreset) -> String {
        "voxii_message_\(preset.rawValue)_\(kind.debugName).wav"
    }

    private func makeMessageToneWAV(for kind: SoundKind, preset: VoxiiMessageSoundPreset, sampleRate: Int) -> Data {
        switch (preset, kind) {
        case (.classic, .send):
            return makeClassicSendToneWAV(sampleRate: sampleRate)
        case (.classic, .incoming):
            return makeClassicIncomingToneWAV(sampleRate: sampleRate)
        case (.glass, .send):
            return makeGlassSendToneWAV(sampleRate: sampleRate)
        case (.glass, .incoming):
            return makeGlassIncomingToneWAV(sampleRate: sampleRate)
        case (.minimal, .send):
            return makeMinimalSendToneWAV(sampleRate: sampleRate)
        case (.minimal, .incoming):
            return makeMinimalIncomingToneWAV(sampleRate: sampleRate)
        case (.off, _):
            return makePCM16MonoWAV(pcm: [], sampleRate: sampleRate)
        }
    }

    private func makeClassicSendToneWAV(sampleRate: Int) -> Data {
        let pulseFrames = Int(Double(sampleRate) * 0.075)
        let tailFrames = Int(Double(sampleRate) * 0.045)
        let fadeFrames = Int(Double(sampleRate) * 0.012)

        var pcm: [Int16] = []
        pcm.reserveCapacity(pulseFrames + tailFrames)

        appendTone(
            into: &pcm,
            sampleRate: sampleRate,
            frames: pulseFrames,
            frequencyA: 1320,
            frequencyB: 1760,
            amplitude: 0.22,
            fadeFrames: fadeFrames
        )
        appendTone(
            into: &pcm,
            sampleRate: sampleRate,
            frames: tailFrames,
            frequencyA: 1760,
            frequencyB: 2093,
            amplitude: 0.18,
            fadeFrames: fadeFrames
        )

        return makePCM16MonoWAV(pcm: pcm, sampleRate: sampleRate)
    }

    private func makeClassicIncomingToneWAV(sampleRate: Int) -> Data {
        let firstPulseFrames = Int(Double(sampleRate) * 0.08)
        let gapFrames = Int(Double(sampleRate) * 0.03)
        let secondPulseFrames = Int(Double(sampleRate) * 0.11)
        let fadeFrames = Int(Double(sampleRate) * 0.014)

        var pcm: [Int16] = []
        pcm.reserveCapacity(firstPulseFrames + gapFrames + secondPulseFrames)

        appendTone(
            into: &pcm,
            sampleRate: sampleRate,
            frames: firstPulseFrames,
            frequencyA: 740,
            frequencyB: 988,
            amplitude: 0.2,
            fadeFrames: fadeFrames
        )
        appendSilence(into: &pcm, frames: gapFrames)
        appendTone(
            into: &pcm,
            sampleRate: sampleRate,
            frames: secondPulseFrames,
            frequencyA: 880,
            frequencyB: 1174,
            amplitude: 0.24,
            fadeFrames: fadeFrames
        )

        return makePCM16MonoWAV(pcm: pcm, sampleRate: sampleRate)
    }

    private func makeGlassSendToneWAV(sampleRate: Int) -> Data {
        let firstFrames = Int(Double(sampleRate) * 0.055)
        let secondFrames = Int(Double(sampleRate) * 0.05)
        let fadeFrames = Int(Double(sampleRate) * 0.012)

        var pcm: [Int16] = []
        pcm.reserveCapacity(firstFrames + secondFrames)

        appendTone(
            into: &pcm,
            sampleRate: sampleRate,
            frames: firstFrames,
            frequencyA: 1480,
            frequencyB: 1976,
            amplitude: 0.18,
            fadeFrames: fadeFrames
        )
        appendTone(
            into: &pcm,
            sampleRate: sampleRate,
            frames: secondFrames,
            frequencyA: 1760,
            frequencyB: 2349,
            amplitude: 0.15,
            fadeFrames: fadeFrames
        )

        return makePCM16MonoWAV(pcm: pcm, sampleRate: sampleRate)
    }

    private func makeGlassIncomingToneWAV(sampleRate: Int) -> Data {
        let pulseFrames = Int(Double(sampleRate) * 0.09)
        let tailFrames = Int(Double(sampleRate) * 0.14)
        let fadeFrames = Int(Double(sampleRate) * 0.016)

        var pcm: [Int16] = []
        pcm.reserveCapacity(pulseFrames + tailFrames)

        appendTone(
            into: &pcm,
            sampleRate: sampleRate,
            frames: pulseFrames,
            frequencyA: 988,
            frequencyB: 1319,
            amplitude: 0.18,
            fadeFrames: fadeFrames
        )
        appendTone(
            into: &pcm,
            sampleRate: sampleRate,
            frames: tailFrames,
            frequencyA: 1174,
            frequencyB: 1568,
            amplitude: 0.22,
            fadeFrames: fadeFrames
        )

        return makePCM16MonoWAV(pcm: pcm, sampleRate: sampleRate)
    }

    private func makeMinimalSendToneWAV(sampleRate: Int) -> Data {
        let frames = Int(Double(sampleRate) * 0.045)
        let fadeFrames = Int(Double(sampleRate) * 0.01)

        var pcm: [Int16] = []
        pcm.reserveCapacity(frames)

        appendTone(
            into: &pcm,
            sampleRate: sampleRate,
            frames: frames,
            frequencyA: 1760,
            frequencyB: 2093,
            amplitude: 0.14,
            fadeFrames: fadeFrames
        )

        return makePCM16MonoWAV(pcm: pcm, sampleRate: sampleRate)
    }

    private func makeMinimalIncomingToneWAV(sampleRate: Int) -> Data {
        let firstFrames = Int(Double(sampleRate) * 0.04)
        let gapFrames = Int(Double(sampleRate) * 0.018)
        let secondFrames = Int(Double(sampleRate) * 0.06)
        let fadeFrames = Int(Double(sampleRate) * 0.01)

        var pcm: [Int16] = []
        pcm.reserveCapacity(firstFrames + gapFrames + secondFrames)

        appendTone(
            into: &pcm,
            sampleRate: sampleRate,
            frames: firstFrames,
            frequencyA: 1047,
            frequencyB: 1397,
            amplitude: 0.14,
            fadeFrames: fadeFrames
        )
        appendSilence(into: &pcm, frames: gapFrames)
        appendTone(
            into: &pcm,
            sampleRate: sampleRate,
            frames: secondFrames,
            frequencyA: 1174,
            frequencyB: 1568,
            amplitude: 0.17,
            fadeFrames: fadeFrames
        )

        return makePCM16MonoWAV(pcm: pcm, sampleRate: sampleRate)
    }

    private func appendTone(
        into buffer: inout [Int16],
        sampleRate: Int,
        frames: Int,
        frequencyA: Double,
        frequencyB: Double,
        amplitude: Double,
        fadeFrames: Int
    ) {
        guard frames > 0 else {
            return
        }

        for frame in 0..<frames {
            let t = Double(frame) / Double(sampleRate)
            let envelope: Double
            if frame < fadeFrames {
                envelope = Double(frame) / Double(max(1, fadeFrames))
            } else if frame > frames - fadeFrames {
                envelope = Double(max(0, frames - frame)) / Double(max(1, fadeFrames))
            } else {
                envelope = 1
            }

            let sample =
                sin(2.0 * .pi * frequencyA * t) * 0.64 +
                sin(2.0 * .pi * frequencyB * t) * 0.36

            let clamped = max(-1.0, min(1.0, sample * amplitude * envelope))
            buffer.append(Int16(clamped * Double(Int16.max)))
        }
    }

    private func appendSilence(into buffer: inout [Int16], frames: Int) {
        guard frames > 0 else {
            return
        }
        buffer.append(contentsOf: repeatElement(0, count: frames))
    }

    private func makePCM16MonoWAV(pcm: [Int16], sampleRate: Int) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = UInt16(numChannels * (bitsPerSample / 8))
        let dataChunkSize = UInt32(pcm.count * MemoryLayout<Int16>.size)
        let riffChunkSize = UInt32(36) + dataChunkSize

        var data = Data()
        data.reserveCapacity(Int(riffChunkSize) + 8)

        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46])
        data.appendLittleEndian(riffChunkSize)
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45])
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20])
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(numChannels)
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(byteRate)
        data.appendLittleEndian(blockAlign)
        data.appendLittleEndian(bitsPerSample)
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61])
        data.appendLittleEndian(dataChunkSize)

        for sample in pcm {
            data.appendLittleEndian(sample)
        }

        return data
    }
}

@MainActor
final class VoxiiRingtonePlayer {
    static let shared = VoxiiRingtonePlayer()

    private var audioPlayer: AVAudioPlayer?
    private var isActive = false
    private var previewTask: Task<Void, Never>?

    private init() {}

    func startIfNeeded() {
        previewTask?.cancel()
        previewTask = nil

        guard !isActive else {
            return
        }

        let preset = VoxiiSoundPreferences.callRingtone
        guard preset != .silent else {
            return
        }

        do {
            let url = try Self.ringtoneFileURL(for: preset)
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0.9
            player.prepareToPlay()
            guard player.play() else {
                print("[VideoCall][Ringtone] Failed to start playback")
                return
            }
            audioPlayer = player
            isActive = true
        } catch {
            print("[VideoCall][Ringtone] Failed to prepare ringtone: \(error.localizedDescription)")
        }
    }

    func previewCurrent() {
        let preset = VoxiiSoundPreferences.callRingtone
        guard preset != .silent else {
            stopIfNeeded()
            return
        }

        stopIfNeeded()
        do {
            let url = try Self.ringtoneFileURL(for: preset)
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0.9
            player.prepareToPlay()
            guard player.play() else {
                return
            }
            audioPlayer = player
            isActive = true
            previewTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_900_000_000)
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    self?.stopPlaybackOnly()
                    self?.previewTask = nil
                }
            }
        } catch {
            print("[VideoCall][Ringtone] Failed to preview ringtone: \(error.localizedDescription)")
        }
    }

    func stopIfNeeded() {
        previewTask?.cancel()
        previewTask = nil
        stopPlaybackOnly()
    }

    private func stopPlaybackOnly() {
        guard isActive else {
            return
        }
        audioPlayer?.stop()
        audioPlayer = nil
        isActive = false
    }

    private static func generatedRingtoneFilename(for preset: VoxiiCallRingtonePreset) -> String {
        preset.filename ?? "voxii_call_ringtone.wav"
    }

    private static func ringtoneFileURL(for preset: VoxiiCallRingtonePreset) throws -> URL {
        if let bundledURL = VoxiiCallSound.bundledRingtoneURL(for: preset) {
            return bundledURL
        }

        let directory = FileManager.default.temporaryDirectory
        let fileURL = directory.appendingPathComponent(generatedRingtoneFilename(for: preset))

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let wavData = makeRingtoneWAV(for: preset, sampleRate: 22_050)
            try wavData.write(to: fileURL, options: .atomic)
        }

        return fileURL
    }

    private static func makeRingtoneWAV(for preset: VoxiiCallRingtonePreset, sampleRate: Int) -> Data {
        switch preset {
        case .voxii:
            return makeVoxiiRingtoneWAV(sampleRate: sampleRate)
        case .crystal:
            return makeCrystalRingtoneWAV(sampleRate: sampleRate)
        case .pulse:
            return makePulseRingtoneWAV(sampleRate: sampleRate)
        case .silent:
            return makePCM16MonoWAV(pcm: [], sampleRate: sampleRate)
        }
    }

    private static func makeVoxiiRingtoneWAV(sampleRate: Int) -> Data {
        let toneAFrames = Int(Double(sampleRate) * 0.30)
        let toneBFrames = Int(Double(sampleRate) * 0.30)
        let shortPauseFrames = Int(Double(sampleRate) * 0.16)
        let longPauseFrames = Int(Double(sampleRate) * 0.86)
        let fadeFrames = Int(Double(sampleRate) * 0.018)

        var pcm: [Int16] = []
        pcm.reserveCapacity((toneAFrames + shortPauseFrames + toneBFrames + longPauseFrames) * 2)

        appendTone(
            into: &pcm,
            sampleRate: sampleRate,
            frames: toneAFrames,
            frequencyA: 932,
            frequencyB: 1397,
            amplitude: 0.34,
            fadeFrames: fadeFrames
        )
        appendSilence(into: &pcm, frames: shortPauseFrames)
        appendTone(
            into: &pcm,
            sampleRate: sampleRate,
            frames: toneBFrames,
            frequencyA: 932,
            frequencyB: 1397,
            amplitude: 0.34,
            fadeFrames: fadeFrames
        )
        appendSilence(into: &pcm, frames: longPauseFrames)

        return makePCM16MonoWAV(pcm: pcm, sampleRate: sampleRate)
    }

    private static func makeCrystalRingtoneWAV(sampleRate: Int) -> Data {
        let brightFrames = Int(Double(sampleRate) * 0.26)
        let brightTailFrames = Int(Double(sampleRate) * 0.26)
        let pauseFrames = Int(Double(sampleRate) * 0.18)
        let fadeFrames = Int(Double(sampleRate) * 0.015)

        var pcm: [Int16] = []
        pcm.reserveCapacity((brightFrames + brightTailFrames + pauseFrames) * 2)

        appendTone(
            into: &pcm,
            sampleRate: sampleRate,
            frames: brightFrames,
            frequencyA: 1319,
            frequencyB: 1760,
            amplitude: 0.2,
            fadeFrames: fadeFrames
        )
        appendSilence(into: &pcm, frames: pauseFrames)
        appendTone(
            into: &pcm,
            sampleRate: sampleRate,
            frames: brightTailFrames,
            frequencyA: 1568,
            frequencyB: 2093,
            amplitude: 0.22,
            fadeFrames: fadeFrames
        )
        appendSilence(into: &pcm, frames: Int(Double(sampleRate) * 0.92))
        appendTone(
            into: &pcm,
            sampleRate: sampleRate,
            frames: brightFrames,
            frequencyA: 1174,
            frequencyB: 1568,
            amplitude: 0.18,
            fadeFrames: fadeFrames
        )
        appendSilence(into: &pcm, frames: pauseFrames)
        appendTone(
            into: &pcm,
            sampleRate: sampleRate,
            frames: brightTailFrames,
            frequencyA: 1480,
            frequencyB: 1976,
            amplitude: 0.2,
            fadeFrames: fadeFrames
        )
        appendSilence(into: &pcm, frames: Int(Double(sampleRate) * 0.92))

        return makePCM16MonoWAV(pcm: pcm, sampleRate: sampleRate)
    }

    private static func makePulseRingtoneWAV(sampleRate: Int) -> Data {
        let firstFrames = Int(Double(sampleRate) * 0.18)
        let secondFrames = Int(Double(sampleRate) * 0.18)
        let thirdFrames = Int(Double(sampleRate) * 0.24)
        let shortPauseFrames = Int(Double(sampleRate) * 0.08)
        let longPauseFrames = Int(Double(sampleRate) * 0.74)
        let fadeFrames = Int(Double(sampleRate) * 0.012)

        var pcm: [Int16] = []
        pcm.reserveCapacity(firstFrames + secondFrames + thirdFrames + shortPauseFrames * 2 + longPauseFrames)

        appendTone(
            into: &pcm,
            sampleRate: sampleRate,
            frames: firstFrames,
            frequencyA: 740,
            frequencyB: 988,
            amplitude: 0.2,
            fadeFrames: fadeFrames
        )
        appendSilence(into: &pcm, frames: shortPauseFrames)
        appendTone(
            into: &pcm,
            sampleRate: sampleRate,
            frames: secondFrames,
            frequencyA: 784,
            frequencyB: 1047,
            amplitude: 0.22,
            fadeFrames: fadeFrames
        )
        appendSilence(into: &pcm, frames: shortPauseFrames)
        appendTone(
            into: &pcm,
            sampleRate: sampleRate,
            frames: thirdFrames,
            frequencyA: 880,
            frequencyB: 1174,
            amplitude: 0.24,
            fadeFrames: fadeFrames
        )
        appendSilence(into: &pcm, frames: longPauseFrames)

        return makePCM16MonoWAV(pcm: pcm, sampleRate: sampleRate)
    }

    private static func appendTone(
        into buffer: inout [Int16],
        sampleRate: Int,
        frames: Int,
        frequencyA: Double,
        frequencyB: Double,
        amplitude: Double,
        fadeFrames: Int
    ) {
        guard frames > 0 else {
            return
        }

        for frame in 0..<frames {
            let t = Double(frame) / Double(sampleRate)
            let envelope: Double
            if frame < fadeFrames {
                envelope = Double(frame) / Double(max(1, fadeFrames))
            } else if frame > frames - fadeFrames {
                envelope = Double(max(0, frames - frame)) / Double(max(1, fadeFrames))
            } else {
                envelope = 1
            }

            let sample =
                sin(2.0 * .pi * frequencyA * t) * 0.62 +
                sin(2.0 * .pi * frequencyB * t) * 0.38

            let clamped = max(-1.0, min(1.0, sample * amplitude * envelope))
            buffer.append(Int16(clamped * Double(Int16.max)))
        }
    }

    private static func appendSilence(into buffer: inout [Int16], frames: Int) {
        guard frames > 0 else {
            return
        }
        buffer.append(contentsOf: repeatElement(0, count: frames))
    }

    private static func makePCM16MonoWAV(pcm: [Int16], sampleRate: Int) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = UInt16(numChannels * (bitsPerSample / 8))
        let dataChunkSize = UInt32(pcm.count * MemoryLayout<Int16>.size)
        let riffChunkSize = UInt32(36) + dataChunkSize

        var data = Data()
        data.reserveCapacity(Int(riffChunkSize) + 8)

        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // RIFF
        data.appendLittleEndian(riffChunkSize)
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // WAVE
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // fmt
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1)) // PCM
        data.appendLittleEndian(numChannels)
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(byteRate)
        data.appendLittleEndian(blockAlign)
        data.appendLittleEndian(bitsPerSample)
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // data
        data.appendLittleEndian(dataChunkSize)

        for sample in pcm {
            data.appendLittleEndian(sample)
        }

        return data
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { bytes in
            append(bytes.bindMemory(to: UInt8.self))
        }
    }
}

struct VideoCallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appearance: VoxiiAppearance

    let config: VideoCallConfig
    let onClose: () -> Void

    @StateObject private var controller = VideoCallController()
    @State private var isAcceptingIncoming = false
    @State private var didAutoAcceptIncoming = false
    
    private var isAudioOnlyCall: Bool {
        config.callType.lowercased() == "audio"
    }

    var body: some View {
        ZStack {
            callBackground
            callStage

            VStack(spacing: 0) {
                topBar
                Spacer()
                VStack(spacing: 12) {
                    statusBanner
                    controlsBar
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 18)

            if controller.state == .incoming {
                incomingOverlay
            }
        }
        .ignoresSafeArea()
        .onAppear {
            controller.statusText = appearance.t("call.connectingShort")
            do {
                try activateCallAudioSession()
            } catch {
                controller.errorMessage = error.localizedDescription
            }
            syncRingtone(for: controller.state)
            attemptAutoAcceptIncomingIfNeeded(for: controller.state)
        }
        .onDisappear {
            VoxiiRingtonePlayer.shared.stopIfNeeded()
            controller.endCall()
            deactivateCallAudioSession()
        }
        .onChange(of: controller.state) { _, newValue in
            syncRingtone(for: newValue)
            attemptAutoAcceptIncomingIfNeeded(for: newValue)
            if newValue == .ended {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    onClose()
                    dismiss()
                }
            }
        }
        .alert(appearance.t("call.errorTitle"), isPresented: Binding(
            get: { controller.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    controller.errorMessage = nil
                }
            }
        )) {
            Button(appearance.t("common.close"), role: .cancel) {
                controller.endCall()
            }
        } message: {
            Text(controller.errorMessage ?? appearance.t("common.unknownError"))
        }
    }

    private var callBackground: some View {
        ZStack {
            VoxiiBackground()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.18),
                    .clear,
                    Color.black.opacity(0.28)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    VoxiiTheme.accentBlue.opacity(0.18),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 320
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    VoxiiTheme.accent.opacity(0.14),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 280
            )
            .ignoresSafeArea()
        }
    }

    private var callStage: some View {
        ZStack {
            VideoCallWebContainer(config: config, controller: controller)
                .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.08),
                                    .clear,
                                    Color.black.opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.screen)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 24, x: 0, y: 18)

            if !controller.hasRemoteVideo && controller.state != .ended {
                callPlaceholderOverlay
                    .padding(.horizontal, 26)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 84)
        .padding(.bottom, 184)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                controller.endCall()
                onClose()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(
                VoxiiRoundButtonStyle(
                    diameter: 44,
                    variant: .neutral
                )
            )

            HStack(spacing: 12) {
                VoxiiAvatarView(
                    text: config.peer.avatar ?? config.peer.username,
                    isOnline: controller.state == .connected || controller.state == .calling
                        || controller.state == .incoming
                        || controller.state == .connecting,
                    size: 42
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(config.peer.username)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(VoxiiTheme.text)
                        .lineLimit(1)
                    Text(controller.statusText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(VoxiiTheme.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(callPanelBackground(cornerRadius: 24, accentOpacity: 0.12))
            .layoutPriority(1)

            Spacer()

            callTypeChip
        }
    }

    private var controlsBar: some View {
        HStack(alignment: .top, spacing: 18) {
            callControl(
                icon: controller.isAudioEnabled ? "mic.fill" : "mic.slash.fill",
                title: appearance.t("call.controlMic"),
                active: controller.isAudioEnabled,
                variant: controller.isAudioEnabled ? .accent : .neutral,
                diameter: 58,
                foregroundColor: controller.isAudioEnabled ? .white : nil,
                action: { controller.toggleAudio() }
            )

            callControl(
                icon: controller.isVideoEnabled ? "video.fill" : "video.slash.fill",
                title: appearance.t("call.controlCamera"),
                active: controller.isVideoEnabled,
                variant: controller.isVideoEnabled ? .accent : .neutral,
                diameter: 58,
                foregroundColor: controller.isVideoEnabled ? .white : nil,
                action: { controller.toggleVideo() }
            )

            callControl(
                icon: "phone.down.fill",
                title: appearance.t("call.controlEnd"),
                active: true,
                variant: .danger,
                diameter: 72,
                foregroundColor: .white,
                action: { controller.endCall() }
            )
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .background(
            callPanelBackground(cornerRadius: 30, accentOpacity: 0.14)
        )
        .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 8)
    }

    private var incomingOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(VoxiiTheme.accentGradient.opacity(0.28))
                        .frame(width: 116, height: 116)
                        .blur(radius: 18)

                    VoxiiAvatarView(
                        text: config.peer.avatar ?? currentCallerName,
                        isOnline: true,
                        size: 88
                    )
                }

                VStack(spacing: 6) {
                    Text(incomingTitle)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(VoxiiTheme.text)

                    Text(currentCallerName)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(VoxiiTheme.muted)
                }

                callTypeChip

                HStack(spacing: 14) {
                    Button {
                        VoxiiRingtonePlayer.shared.stopIfNeeded()
                        controller.rejectIncoming()
                    } label: {
                        Label(appearance.t("call.decline"), systemImage: "phone.down.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(VoxiiGradientButtonStyle(variant: .danger))

                    Button {
                        Task { await acceptIncomingWithPermissions() }
                    } label: {
                        if isAcceptingIncoming {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity, minHeight: 20)
                        } else {
                            Label(appearance.t("call.accept"), systemImage: "phone.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(VoxiiGradientButtonStyle())
                    .disabled(isAcceptingIncoming)
                }
            }
            .padding(28)
            .background(
                callPanelBackground(cornerRadius: 32, accentOpacity: 0.18)
            )
            .shadow(color: .black.opacity(0.34), radius: 26, x: 0, y: 16)
            .padding(.horizontal, 24)
        }
    }

    private var placeholderText: String {
        switch controller.state {
        case .connecting:
            return appearance.t("call.connectingEngine")
        case .calling:
            return appearance.tf("call.callingUser", config.peer.username)
        case .incoming:
            return appearance.t("call.incoming")
        case .connected:
            return appearance.t("call.waitingRemoteVideo")
        case .ended:
            return appearance.t("call.ended")
        }
    }

    private var currentCallerName: String {
        controller.incomingCallerName ?? config.peer.username
    }

    private var incomingTitle: String {
        appearance.t(isAudioOnlyCall ? "call.incomingAudio" : "call.incomingVideo")
    }

    private var callTypeTitle: String {
        appearance.t(isAudioOnlyCall ? "call.audio" : "call.video")
    }

    private var callTypeIcon: String {
        isAudioOnlyCall ? "waveform" : "video.fill"
    }

    private var statusBanner: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusAccentColor)
                .frame(width: 10, height: 10)
                .shadow(color: statusAccentColor.opacity(0.36), radius: 6, x: 0, y: 0)

            Text(controller.statusText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(VoxiiTheme.text)
                .lineLimit(1)

            Spacer(minLength: 0)

            Image(systemName: callTypeIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VoxiiTheme.muted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(callPanelBackground(cornerRadius: 20, accentOpacity: 0.08))
    }

    private var callPlaceholderOverlay: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(VoxiiTheme.accentGradient.opacity(0.22))
                    .frame(width: 118, height: 118)
                    .blur(radius: 20)

                VoxiiAvatarView(
                    text: config.peer.avatar ?? currentCallerName,
                    isOnline: controller.state != .ended,
                    size: 88
                )
            }

            VStack(spacing: 6) {
                Text(currentCallerName)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(VoxiiTheme.text)

                Text(placeholderText)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(VoxiiTheme.muted)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 8) {
                Image(systemName: callTypeIcon)
                    .font(.system(size: 12, weight: .bold))
                Text(callTypeTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(VoxiiTheme.text.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(callPanelBackground(cornerRadius: 18, accentOpacity: 0.06))
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .background(callPanelBackground(cornerRadius: 32, accentOpacity: 0.16))
        .shadow(color: .black.opacity(0.28), radius: 24, x: 0, y: 16)
    }

    private var callTypeChip: some View {
        HStack(spacing: 7) {
            Image(systemName: callTypeIcon)
                .font(.system(size: 12, weight: .bold))
            Text(callTypeTitle)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(callPanelBackground(cornerRadius: 20, accentOpacity: 0.16))
    }

    private func callControl(
        icon: String,
        title: String,
        active: Bool,
        variant: VoxiiButtonVariant,
        diameter: CGFloat,
        foregroundColor: Color?,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: diameter >= 70 ? 20 : 18, weight: .bold))
            }
            .buttonStyle(
                VoxiiRoundButtonStyle(
                    diameter: diameter,
                    variant: variant,
                    foregroundColor: foregroundColor
                )
            )

            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(active ? VoxiiTheme.text : VoxiiTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private func callPanelBackground(cornerRadius: CGFloat, accentOpacity: Double) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.black.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.82)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                VoxiiTheme.glassStrong.opacity(0.8),
                                Color.black.opacity(0.22)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                VoxiiTheme.accentBlue.opacity(accentOpacity),
                                .clear
                            ],
                            center: .topLeading,
                            startRadius: 8,
                            endRadius: 220
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.16),
                                Color.white.opacity(0.04),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.screen)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.16), lineWidth: 0.6)
                    .padding(1)
            )
    }

    private var statusAccentColor: Color {
        switch controller.state {
        case .connecting:
            return VoxiiTheme.accentBlue
        case .calling:
            return VoxiiTheme.accent
        case .incoming:
            return Color(hex: "#F59E0B") ?? .orange
        case .connected:
            return VoxiiTheme.online
        case .ended:
            return VoxiiTheme.danger
        }
    }

    private func acceptIncomingWithPermissions() async {
        guard !isAcceptingIncoming else {
            return
        }

        VoxiiRingtonePlayer.shared.stopIfNeeded()
        isAcceptingIncoming = true
        defer { isAcceptingIncoming = false }

        let microphoneGranted = await requestMicrophonePermission()
        guard microphoneGranted else {
            controller.errorMessage = appearance.t("call.microphoneRequired")
            return
        }

        let isAudioOnlyCall = config.callType.lowercased() == "audio"
        if !isAudioOnlyCall {
            let cameraGranted = await requestCameraPermission()
            guard cameraGranted else {
                controller.errorMessage = appearance.t("call.cameraRequired")
                return
            }
        }

        do {
            try activateCallAudioSession()
        } catch {
            controller.errorMessage = error.localizedDescription
            return
        }

        controller.acceptIncoming()
    }

    private func syncRingtone(for state: VideoCallState) {
        if state == .incoming {
            VoxiiRingtonePlayer.shared.startIfNeeded()
        } else {
            VoxiiRingtonePlayer.shared.stopIfNeeded()
        }
    }

    private func attemptAutoAcceptIncomingIfNeeded(for state: VideoCallState) {
        guard config.autoAcceptIncoming,
              state == .incoming,
              !didAutoAcceptIncoming else {
            return
        }
        didAutoAcceptIncoming = true
        Task { await acceptIncomingWithPermissions() }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func requestCameraPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func activateCallAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
            .playAndRecord,
            mode: .videoChat,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
        )
        try audioSession.setActive(true)
    }

    private func deactivateCallAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

private struct VideoCallWebContainer: UIViewRepresentable {
    let config: VideoCallConfig
    @ObservedObject var controller: VideoCallController

    func makeCoordinator() -> Coordinator {
        Coordinator(config: config, controller: controller)
    }

    func makeUIView(context: Context) -> WKWebView {
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "voxiiCall")

        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.userContentController = userContentController
        webConfiguration.allowsInlineMediaPlayback = true
        webConfiguration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        context.coordinator.bind(webView: webView)
        webView.loadHTMLString(context.coordinator.buildHTML(), baseURL: context.coordinator.baseURL)

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) { }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
        private let config: VideoCallConfig
        private let controller: VideoCallController
        private(set) var baseURL: URL?
        private weak var webView: WKWebView?

        init(config: VideoCallConfig, controller: VideoCallController) {
            self.config = config
            self.controller = controller

            let normalized = VoxiiURLBuilder.normalizeBaseURL(config.baseServerURL)
            self.baseURL = normalized
            super.init()
        }

        func bind(webView: WKWebView) {
            self.webView = webView
            controller.attach(webView: webView)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "voxiiCall",
                  let payload = message.body as? [String: Any] else {
                return
            }

            Task { @MainActor in
                controller.handle(payload: payload)
            }
        }

        @available(iOS 15.0, *)
        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            decisionHandler(.grant)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                controller.handle(payload: [
                    "type": "error",
                    "message": error.localizedDescription
                ])
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                controller.handle(payload: [
                    "type": "error",
                    "message": error.localizedDescription
                ])
            }
        }

        func buildHTML() -> String {
            struct Bootstrap: Encodable {
                let serverURL: String
                let token: String
                let mode: String
                let callType: String
                let selfId: Int
                let selfUsername: String
                let peerId: Int
                let peerUsername: String
                let initialIncomingSocketId: String?
                let initialIncomingUserId: Int?
                let initialIncomingUsername: String?
                let initialIncomingAvatar: String?
            }

            func hexWithAlpha(_ hex: String, alpha: UInt8) -> String {
                let normalized = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
                guard normalized.count == 6 else {
                    return "#00000000"
                }
                return "#\(normalized)\(String(format: "%02X", alpha))"
            }

            let normalizedServer = (baseURL?.absoluteString ?? config.baseServerURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            let bootstrap = Bootstrap(
                serverURL: normalizedServer,
                token: config.token,
                mode: config.mode.rawValue,
                callType: config.callType,
                selfId: config.selfUser?.id ?? 0,
                selfUsername: config.selfUser?.username ?? localizedUnknownLabel(),
                peerId: config.peer.id,
                peerUsername: config.peer.username,
                initialIncomingSocketId: config.initialIncomingSocketId,
                initialIncomingUserId: config.initialIncomingUserId,
                initialIncomingUsername: config.initialIncomingUsername,
                initialIncomingAvatar: config.initialIncomingAvatar
            )

            let data = (try? JSONEncoder().encode(bootstrap)) ?? Data("{}".utf8)
            let json = String(data: data, encoding: .utf8) ?? "{}"
            let socketScriptURL = "\(normalizedServer)/socket.io/socket.io.js"

            let bg0Hex = VoxiiTheme.bg0.toHexString() ?? "#0A0F18"
            let bg1Hex = VoxiiTheme.bg1.toHexString() ?? "#0C1322"
            let accentHex = VoxiiTheme.accent.toHexString() ?? "#8B5CF6"
            let accentBlueHex = VoxiiTheme.accentBlue.toHexString() ?? "#60A5FA"
            let onlineHex = VoxiiTheme.online.toHexString() ?? "#22C55E"
            let accentSoft = hexWithAlpha(accentHex, alpha: 56)
            let accentBlueSoft = hexWithAlpha(accentBlueHex, alpha: 46)
            let onlineSoft = hexWithAlpha(onlineHex, alpha: 24)

            return """
            <!doctype html>
            <html>
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover, user-scalable=no">
              <style>
                :root {
                  color-scheme: dark;
                }
                * { box-sizing: border-box; }
                html, body {
                  margin: 0;
                  width: 100%;
                  height: 100%;
                  overflow: hidden;
                  background: radial-gradient(1200px 800px at 20% 20%, \(accentSoft), transparent 52%),
                              radial-gradient(900px 700px at 80% 15%, \(accentBlueSoft), transparent 55%),
                              radial-gradient(900px 700px at 70% 88%, \(onlineSoft), transparent 56%),
                              linear-gradient(180deg, \(bg0Hex), \(bg1Hex));
                }
                #stage {
                  position: fixed;
                  inset: 0;
                }
                video {
                  background: #070b12;
                  border: 0;
                  outline: 0;
                }
                #remoteVideo {
                  position: absolute;
                  inset: 0;
                  width: 100%;
                  height: 100%;
                  object-fit: cover;
                }
                #localVideo {
                  position: absolute;
                  top: 18px;
                  right: 18px;
                  width: min(36vw, 164px);
                  aspect-ratio: 3 / 4;
                  object-fit: cover;
                  border-radius: 14px;
                  border: 1px solid rgba(255,255,255,.22);
                  box-shadow: 0 10px 30px rgba(0,0,0,.45);
                  z-index: 6;
                }
              </style>
              <script src="\(socketScriptURL)"></script>
            </head>
            <body>
              <div id="stage">
                <video id="remoteVideo" autoplay playsinline></video>
                <video id="localVideo" autoplay playsinline muted></video>
              </div>
              <script>
                const cfg = \(json);

                let socket = null;
                let localStream = null;
                let peerConnection = null;
                let currentPeerSocketId = null;
                let pendingCandidates = [];
                let incomingCall = null;
                let ended = false;

                const remoteVideo = document.getElementById('remoteVideo');
                const localVideo = document.getElementById('localVideo');

                function post(type, payload = {}) {
                  if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.voxiiCall) return;
                  window.webkit.messageHandlers.voxiiCall.postMessage(Object.assign({ type }, payload));
                }

                function setState(state) {
                  post('state', { state });
                }

                function setStatus(text) {
                  post('status', { text });
                }

                function updateAudio(enabled) {
                  post('audio', { enabled });
                }

                function updateVideo(enabled) {
                  post('video', { enabled });
                }

                function updateRemote(hasRemote) {
                  post('remote', { hasRemote });
                }

                function buildRTCConfig() {
                  return {
                    iceServers: [
                      { urls: 'stun:stun.l.google.com:19302' },
                      { urls: 'stun:stun1.l.google.com:19302' },
                      { urls: 'turn:openrelay.metered.ca:80', username: 'openrelayproject', credential: 'openrelayproject' },
                      { urls: 'turn:openrelay.metered.ca:443', username: 'openrelayproject', credential: 'openrelayproject' }
                    ],
                    iceCandidatePoolSize: 10
                  };
                }

                async function ensureLocalMedia(callType = 'video') {
                  if (localStream) return localStream;

                  localStream = await navigator.mediaDevices.getUserMedia({
                    video: {
                      width: { ideal: 1280 },
                      height: { ideal: 720 }
                    },
                    audio: {
                      echoCancellation: true,
                      noiseSuppression: true,
                      autoGainControl: true
                    }
                  });

                  if (callType === 'audio') {
                    localStream.getVideoTracks().forEach(track => { track.enabled = false; });
                  }

                  localVideo.srcObject = localStream;
                  localVideo.play().catch(() => {});

                  const audioTrack = localStream.getAudioTracks()[0];
                  const videoTrack = localStream.getVideoTracks()[0];
                  updateAudio(audioTrack ? audioTrack.enabled : true);
                  updateVideo(videoTrack ? videoTrack.enabled : true);
                  return localStream;
                }

                function createPeerConnection(isInitiator) {
                  if (peerConnection) {
                    return peerConnection;
                  }

                  peerConnection = new RTCPeerConnection(buildRTCConfig());

                  if (localStream) {
                    localStream.getTracks().forEach(track => {
                      peerConnection.addTrack(track, localStream);
                    });
                  }

                  peerConnection.onicecandidate = (event) => {
                    if (event.candidate && socket && currentPeerSocketId) {
                      socket.emit('ice-candidate', {
                        to: currentPeerSocketId,
                        candidate: event.candidate,
                        from: socket.id
                      });
                    }
                  };

                  peerConnection.ontrack = (event) => {
                    if (event.streams && event.streams[0]) {
                      remoteVideo.srcObject = event.streams[0];
                      remoteVideo.muted = false;
                      remoteVideo.play().catch(() => {});
                      updateRemote(true);
                      setState('connected');
                      setStatus('In call');
                    }
                  };

                  peerConnection.onconnectionstatechange = () => {
                    if (!peerConnection) return;
                    const state = peerConnection.connectionState;
                    if (state === 'connected') {
                      setState('connected');
                      setStatus('In call');
                    }
                    if (state === 'disconnected' || state === 'failed' || state === 'closed') {
                      endCallInternal(false);
                    }
                  };

                  if (isInitiator) {
                    peerConnection.createOffer({ offerToReceiveAudio: true, offerToReceiveVideo: true })
                      .then(offer => peerConnection.setLocalDescription(offer))
                      .then(() => {
                        if (socket && currentPeerSocketId) {
                          socket.emit('offer', {
                            to: currentPeerSocketId,
                            offer: peerConnection.localDescription,
                            from: socket.id
                          });
                        }
                      })
                      .catch(error => {
                        post('error', { message: error.message || 'Failed to create offer.' });
                      });
                  }

                  return peerConnection;
                }

                function flushPendingCandidates() {
                  if (!peerConnection || !peerConnection.remoteDescription || pendingCandidates.length === 0) return;
                  pendingCandidates.forEach(candidate => {
                    peerConnection.addIceCandidate(new RTCIceCandidate(candidate)).catch(() => {});
                  });
                  pendingCandidates = [];
                }

                async function handleOffer(data) {
                  currentPeerSocketId = data.from;
                  await ensureLocalMedia(cfg.callType);
                  createPeerConnection(false);
                  await peerConnection.setRemoteDescription(new RTCSessionDescription(data.offer));
                  flushPendingCandidates();
                  const answer = await peerConnection.createAnswer();
                  await peerConnection.setLocalDescription(answer);
                  socket.emit('answer', {
                    to: currentPeerSocketId,
                    answer: peerConnection.localDescription,
                    from: socket.id
                  });
                }

                async function handleAnswer(data) {
                  if (!peerConnection) return;
                  await peerConnection.setRemoteDescription(new RTCSessionDescription(data.answer));
                  flushPendingCandidates();
                }

                function handleIce(data) {
                  if (!peerConnection) return;
                  if (peerConnection.remoteDescription) {
                    peerConnection.addIceCandidate(new RTCIceCandidate(data.candidate)).catch(() => {});
                  } else {
                    pendingCandidates.push(data.candidate);
                  }
                }

                function bindSocketHandlers() {
                  if (window.__voxiiCallHandlersBound) return;
                  window.__voxiiCallHandlersBound = true;

                  socket.on('incoming-call', (data) => {
                    incomingCall = data;
                    setState('incoming');
                    setStatus(`Incoming call from ${data?.from?.username || cfg.peerUsername}`);
                    post('incoming', {
                      caller: data?.from?.username || 'Unknown',
                      callType: data?.type || 'video'
                    });
                  });

                  socket.on('call-accepted', (data) => {
                    const from = data.from || {};
                    if (cfg.mode === 'outgoing') {
                      currentPeerSocketId = from.socketId || null;
                    } else if (!currentPeerSocketId && from.socketId) {
                      currentPeerSocketId = from.socketId;
                    }
                    setState('connecting');
                    if (cfg.mode === 'outgoing') {
                      setStatus(`Connecting to ${from.username || cfg.peerUsername}...`);
                    } else {
                      setStatus('Establishing secure connection...');
                    }
                    createPeerConnection(cfg.mode === 'outgoing');
                  });

                  socket.on('call-rejected', () => {
                    setStatus('Call rejected');
                    endCallInternal(false);
                  });

                  socket.on('call-ended', () => {
                    if (ended) return;
                    setStatus('Call ended');
                    endCallInternal(true);
                  });

                  socket.on('user-left-call', () => {
                    if (ended) return;
                    setStatus('Peer left the call');
                    endCallInternal(true);
                  });

                  socket.on('offer', (data) => {
                    handleOffer(data).catch(error => {
                      post('error', { message: error.message || 'Failed to process offer.' });
                    });
                  });

                  socket.on('answer', (data) => {
                    handleAnswer(data).catch(error => {
                      post('error', { message: error.message || 'Failed to process answer.' });
                    });
                  });

                  socket.on('ice-candidate', (data) => {
                    handleIce(data);
                  });
                }

                function connectSocket() {
                  return new Promise((resolve, reject) => {
                    if (typeof io === 'undefined') {
                      reject(new Error('Socket.IO client is not loaded.'));
                      return;
                    }

                    socket = io(cfg.serverURL, {
                      auth: { token: cfg.token },
                      transports: ['websocket']
                    });

                    socket.on('connect', () => {
                      bindSocketHandlers();
                      resolve();
                    });

                    socket.on('connect_error', (error) => {
                      reject(error);
                    });
                  });
                }

                async function startOutgoing() {
                  await ensureLocalMedia(cfg.callType);
                  setState('calling');
                  setStatus(`Calling ${cfg.peerUsername}...`);
                  socket.emit('initiate-call', {
                    to: cfg.peerId,
                    type: cfg.callType,
                    from: {
                      id: cfg.selfId,
                      username: cfg.selfUsername,
                      socketId: socket.id
                    }
                  });
                }

                async function acceptIncomingCall() {
                  if (!incomingCall || !incomingCall.from || !incomingCall.from.socketId) return;
                  const caller = incomingCall.from;
                  currentPeerSocketId = caller.socketId;
                  await ensureLocalMedia(incomingCall.type || cfg.callType);
                  socket.emit('accept-call', {
                    to: caller.socketId,
                    from: {
                      id: cfg.selfId,
                      username: cfg.selfUsername,
                      socketId: socket.id
                    }
                  });
                  setState('connecting');
                  setStatus(`Connecting to ${caller.username || cfg.peerUsername}...`);
                  createPeerConnection(false);
                  incomingCall = null;
                }

                function rejectIncomingCall() {
                  if (incomingCall && incomingCall.from && incomingCall.from.socketId && socket) {
                    socket.emit('reject-call', { to: incomingCall.from.socketId });
                  }
                  incomingCall = null;
                  endCallInternal(false);
                }

                function endCallInternal(notifyPeer) {
                  if (ended) return;
                  ended = true;

                  if (notifyPeer && socket && currentPeerSocketId) {
                    socket.emit('end-call', { to: currentPeerSocketId });
                  }

                  if (peerConnection) {
                    try { peerConnection.close(); } catch (_) {}
                    peerConnection = null;
                  }

                  if (localStream) {
                    localStream.getTracks().forEach(track => track.stop());
                    localStream = null;
                  }

                  remoteVideo.srcObject = null;
                  updateRemote(false);
                  setState('ended');
                  post('ended', {});

                  if (socket) {
                    setTimeout(() => {
                      socket.disconnect();
                    }, 50);
                  }
                }

                function toggleAudio() {
                  if (!localStream) return;
                  localStream.getAudioTracks().forEach(track => {
                    track.enabled = !track.enabled;
                  });
                  const track = localStream.getAudioTracks()[0];
                  updateAudio(track ? track.enabled : false);
                }

                function toggleVideo() {
                  if (!localStream) return;
                  localStream.getVideoTracks().forEach(track => {
                    track.enabled = !track.enabled;
                  });
                  const track = localStream.getVideoTracks()[0];
                  updateVideo(track ? track.enabled : false);
                }

                window.voxii = {
                  toggleAudio,
                  toggleVideo,
                  endCall: () => endCallInternal(true),
                  acceptIncoming: () => {
                    acceptIncomingCall().catch(error => {
                      post('error', { message: error.message || 'Failed to accept call.' });
                    });
                  },
                  rejectIncoming: rejectIncomingCall
                };

                async function bootstrap() {
                  setState('connecting');
                  setStatus('Connecting to signaling...');

                  try {
                    if (!cfg.token) {
                      throw new Error('Missing auth token.');
                    }

                    await connectSocket();

                    if (cfg.mode === 'outgoing') {
                      await startOutgoing();
                    } else {
                      if (cfg.initialIncomingSocketId) {
                        incomingCall = {
                          from: {
                            id: cfg.initialIncomingUserId || cfg.peerId,
                            username: cfg.initialIncomingUsername || cfg.peerUsername,
                            socketId: cfg.initialIncomingSocketId,
                            avatar: cfg.initialIncomingAvatar || null
                          },
                          type: cfg.callType
                        };
                        setState('incoming');
                        setStatus(`Incoming call from ${incomingCall.from.username || cfg.peerUsername}`);
                        post('incoming', {
                          caller: incomingCall.from.username || cfg.peerUsername,
                          callType: incomingCall.type || cfg.callType
                        });
                      } else {
                        setState('incoming');
                        setStatus('Waiting for incoming call...');
                      }
                    }
                  } catch (error) {
                    post('error', { message: error.message || 'Call initialization failed.' });
                    endCallInternal(false);
                  }
                }

                bootstrap();
              </script>
            </body>
            </html>
            """
        }

        private func localizedUnknownLabel() -> String {
            voxiiPrefersRussianLanguage() ? "Неизвестно" : "Unknown"
        }
    }
}
