import SwiftUI
import Combine
import UniformTypeIdentifiers
import AVFoundation
import WebKit

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

struct ChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var appearance: VoxiiAppearance

    let peer: APIUser

    @State private var messages: [DirectMessage] = []
    @State private var messageText = ""
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
        .confirmationDialog("Delete message?", isPresented: $isDeleteDialogPresented, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let messageID = messageIdForDelete else {
                    return
                }
                Task { await deleteMessage(messageID) }
            }
            Button("Cancel", role: .cancel) {
                messageIdForDelete = nil
            }
        }
        .alert("Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Unknown error")
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
            .buttonStyle(VoxiiGradientButtonStyle(isCompact: true, variant: .neutral))

            VoxiiAvatarView(
                text: peer.avatar ?? peer.username,
                isOnline: peer.status?.lowercased() == "online",
                size: 40
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(peer.username)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(VoxiiTheme.text)

                Text(peer.status ?? "Offline")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(peer.status?.lowercased() == "online" ? VoxiiTheme.online : VoxiiTheme.muted)
            }

            Spacer()

            Button {
                isVideoCallPresented = true
            } label: {
                Image(systemName: "video.fill")
                    .font(.system(size: 14, weight: .bold))
            }
            .buttonStyle(VoxiiGradientButtonStyle(isCompact: true))
            .disabled(session.token == nil || isSending || isRecordingVoice)

            Button {
                Task { await loadMessages() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .bold))
            }
            .buttonStyle(VoxiiGradientButtonStyle(isCompact: true, variant: .neutral))
            .disabled(isSyncing)
        }
        .voxiiCard(cornerRadius: 18, padding: 12)
    }

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
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
                            onOpenFile: { url in
                                openURL(url)
                            }
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
            }
            .onChange(of: messages.count) { _, _ in
                guard let lastID = messages.last?.id else {
                    return
                }
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
        .voxiiCard(cornerRadius: 18, padding: 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let editingMessage {
                actionBanner(
                    title: "Editing message",
                    detail: previewText(for: editingMessage),
                    onCancel: {
                        self.editingMessage = nil
                        messageText = ""
                    }
                )
            } else if let replyToMessage {
                actionBanner(
                    title: "Replying to \(replyToMessage.username ?? "Unknown")",
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

            HStack(alignment: .bottom, spacing: 10) {
                HStack(alignment: .bottom, spacing: 10) {
                    Button {
                        isFileImporterPresented = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(VoxiiTheme.accent)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(.thinMaterial)
                            )
                            .overlay(
                                Circle()
                                    .fill(VoxiiTheme.accent.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending || isRecordingVoice || editingMessage != nil)

                    TextField(composerPlaceholder, text: $messageText, axis: .vertical)
                        .lineLimit(1...4)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(VoxiiTheme.text)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled(false)
                        .disabled(isRecordingVoice)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(minHeight: VoxiiTheme.controlHeightRegular)
                .background(
                    RoundedRectangle(cornerRadius: VoxiiTheme.radiusXL, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .background(
                    RoundedRectangle(cornerRadius: VoxiiTheme.radiusXL, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    VoxiiTheme.glassStrong.opacity(0.76),
                                    VoxiiTheme.glass.opacity(0.7),
                                    VoxiiTheme.accentBlue.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: VoxiiTheme.radiusXL, style: .continuous)
                        .stroke(VoxiiTheme.stroke.opacity(0.7), lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: VoxiiTheme.radiusXL, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.16), Color.white.opacity(0.02)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: VoxiiTheme.accentBlue.opacity(0.05), radius: 6, x: 0, y: 3)
                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)

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
                .buttonStyle(VoxiiRoundButtonStyle(diameter: 44, variant: composerActionVariant))
                .disabled(composerActionDisabled)
            }
        }
        .padding(.horizontal, 2)
    }

    private var composerPlaceholder: String {
        editingMessage == nil ? "Message" : "Update message"
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

    private func handleComposerActionTap() {
        guard !isSending else {
            return
        }

        if isRecordingVoice {
            toggleVoiceRecording()
            return
        }

        if canSend {
            Task { await sendOrUpdate() }
            return
        }

        guard canStartVoiceFromAction else {
            return
        }
        toggleVoiceRecording()
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

    private func actionBanner(title: String, detail: String, onCancel: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
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
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(VoxiiTheme.glass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(VoxiiTheme.stroke, lineWidth: 1)
        )
    }

    private func attachmentBanner(_ attachment: PendingAttachment) -> some View {
        HStack(spacing: 10) {
            Image(systemName: attachment.isAudio ? "waveform" : "doc.fill")
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
                        Text("Transcribe")
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
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(VoxiiTheme.glass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(VoxiiTheme.stroke, lineWidth: 1)
        )
    }

    private var voiceRecordingBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "record.circle.fill")
                .foregroundStyle(.red)

            Text("Recording voice message...")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(VoxiiTheme.text)

            Spacer()

            Button("Cancel") {
                finishVoiceRecording(save: false)
            }
            .buttonStyle(VoxiiGradientButtonStyle(isCompact: true, variant: .neutral))
            .disabled(isSending)

            Button("Stop") {
                finishVoiceRecording(save: true)
            }
            .buttonStyle(VoxiiGradientButtonStyle(isCompact: true))
            .disabled(isSending)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(VoxiiTheme.glass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(VoxiiTheme.stroke, lineWidth: 1)
        )
    }

    private func loadMessages() async {
        guard !isSyncing else {
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
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

            if mergedMessages != messages {
                messages = mergedMessages
            }
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
                    throw APIClientError.server("Message cannot be empty.")
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
                        return voiceFallbackText(for: uploadedAttachment)
                    }
                    return trimmedText
                }()

                if preparedText.isEmpty && uploadedFileId == nil {
                    throw APIClientError.server("Message cannot be empty.")
                }
                var sentMessage: DirectMessage

                do {
                    print("[ChatView][Send] Sending DM textLength=\(preparedText.count) fileId=\(requestFileIdDebug) uploadFileId=\(fileIdDebug) replyToId=\(replyIdDebug)")
                    sentMessage = try await session.sendMessage(
                        to: peer.id,
                        text: preparedText,
                        fileId: requestFileId,
                        file: uploadedAttachment,
                        replyToId: replyToMessage?.id,
                        isVoiceMessage: isVoiceAttachment ? true : nil
                    )
                } catch {
                    guard shouldRetryWithVoiceURL(after: error),
                          isVoiceAttachment,
                          preparedText.isEmpty,
                          uploadedAttachment != nil else {
                        throw error
                    }

                    let fallbackText = voiceFallbackText(for: uploadedAttachment)
                    print("[ChatView][Send] Retrying DM with voice fallback textLength=\(fallbackText.count) fileId=\(fileIdDebug)")
                    sentMessage = try await session.sendMessage(
                        to: peer.id,
                        text: fallbackText,
                        fileId: requestFileId,
                        file: uploadedAttachment,
                        replyToId: replyToMessage?.id,
                        isVoiceMessage: true
                    )
                }

                if uploadedFileId != nil && sentMessage.file == nil {
                    print("[ChatView][Send] Warning: DM saved without attached file in response (messageId=\(sentMessage.id))")
                    if let uploadedAttachment {
                        if isVoiceAttachment,
                           DMMessageTextPolicy.voiceUploadReference(from: sentMessage.content) == nil {
                            let fallbackText = voiceFallbackText(for: uploadedAttachment)
                            if DMMessageTextPolicy.voiceUploadReference(from: fallbackText) != nil {
                                sentMessage = messageWithOverriddenContent(sentMessage, content: fallbackText)
                            }
                        }
                        localAttachmentByMessageID[sentMessage.id] = uploadedAttachment
                        sentMessage = messageWithOverriddenFile(sentMessage, file: uploadedAttachment)
                    }
                } else if let attachedFile = sentMessage.file {
                    localAttachmentByMessageID[sentMessage.id] = attachedFile
                }

                upsertMessage(sentMessage)
            }

            messageText = ""
            replyToMessage = nil
            editingMessage = nil
            pendingAttachment = nil
            errorMessage = nil
            await loadMessages()
        } catch {
            print("[ChatView][Send] Failed: \(error.localizedDescription)")
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func shouldRetryWithVoiceURL(after error: Error) -> Bool {
        let message = ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription).lowercased()
        return message.contains("message text is required")
            || message.contains("text is required")
            || message.contains("text or file is required")
    }

    private func voiceFallbackText(for attachment: APIFileAttachment?) -> String {
        guard let attachment else {
            return DMMessageTextPolicy.invisibleFallbackText
        }

        if let reference = DMMessageTextPolicy.voiceUploadReference(from: attachment.url) {
            return reference
        }

        if let absolute = session.absoluteURL(for: attachment.url)?.absoluteString,
           let reference = DMMessageTextPolicy.voiceUploadReference(from: absolute) {
            return reference
        }

        return DMMessageTextPolicy.invisibleFallbackText
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
            ("\(baseName).m4a", "audio/m4a"),          // iOS voice format
            ("\(baseName).m4a", "audio/mp4"),          // MIME fallback with voice extension
            ("\(baseName).webm", "audio/webm")         // web-compatible fallback
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

        throw lastError ?? APIClientError.server("Failed to upload voice message.")
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
                throw APIClientError.server("File is too large. Maximum size is 10MB.")
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
            errorMessage = "Voice recording is disabled while editing a message."
            return
        }

        guard pendingAttachment == nil else {
            errorMessage = "Remove current attachment before recording."
            return
        }

        let granted = await requestMicrophonePermission()
        guard granted else {
            errorMessage = "Microphone access denied. Enable it in iOS Settings."
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
                throw APIClientError.server("Unable to start voice recording.")
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
            errorMessage = "Voice message is too short."
            return
        }

        guard let voiceRecordingURL else {
            errorMessage = "Recorded file not found."
            return
        }

        do {
            let data = try Data(contentsOf: voiceRecordingURL)
            if data.count > 10 * 1024 * 1024 {
                throw APIClientError.server("Voice message is too large. Maximum size is 10MB.")
            }

            let filename = "voice_message_\(Int(Date().timeIntervalSince1970)).m4a"
            let mimeType = "audio/m4a"
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
                throw APIClientError.server("No speech detected in selected audio.")
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
            return "Attachment: \(file.filename)"
        }

        if DMMessageTextPolicy.voiceUploadReference(from: message.content) != nil {
            return "Voice message"
        }

        return "No text"
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
        HStack {
            if isOutgoing {
                Spacer(minLength: 40)
            }

            VStack(alignment: .leading, spacing: 7) {
                header

                if let reply = message.replyTo {
                    replyBlock(reply)
                }

                if !visibleMessageContent.isEmpty {
                    Text(visibleMessageContent)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .lineSpacing(2)
                        .foregroundStyle(isOutgoing ? .white : VoxiiTheme.text)
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
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    if !isOutgoing {
                        RoundedRectangle(cornerRadius: bubbleCornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }

                    RoundedRectangle(cornerRadius: bubbleCornerRadius, style: .continuous)
                        .fill(bubbleFillStyle)

                    RoundedRectangle(cornerRadius: bubbleCornerRadius, style: .continuous)
                        .fill(bubbleGlossStyle)
                        .blendMode(.screen)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: bubbleCornerRadius, style: .continuous)
                    .stroke(bubbleStrokeStyle, lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: max(8, bubbleCornerRadius - 2), style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.4)
            )
            .shadow(color: bubbleShadowColor, radius: 10, x: 0, y: 6)

            if !isOutgoing {
                Spacer(minLength: 40)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if !isOutgoing {
                Text(message.username ?? "Unknown")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(VoxiiTheme.accentLight)
            }

            if message.edited {
                Text("edited")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(isOutgoing ? 0.14 : 0.08))
                    )
                    .foregroundStyle(isOutgoing ? Color.white.opacity(0.78) : VoxiiTheme.muted)
            }

            Spacer(minLength: 0)

            Text(MessageDate.shortTime(message.createdAt))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(isOutgoing ? 0.16 : 0.09))
                )
                .foregroundStyle(isOutgoing ? Color.white.opacity(0.78) : VoxiiTheme.muted)
        }
    }

    private func replyBlock(_ reply: ReplyPreview) -> some View {
        let visibleReplyText = DMMessageTextPolicy.visibleOptionalText(
            reply.text,
            hasAttachment: reply.file != nil
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let replyVoiceURL = DMMessageTextPolicy.voiceUploadReference(from: reply.text ?? "")

        return VStack(alignment: .leading, spacing: 2) {
            Text("↪ \(reply.author ?? "Unknown")")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(isOutgoing ? Color.white.opacity(0.9) : VoxiiTheme.accentLight)

            if let text = visibleReplyText, !text.isEmpty {
                Text(text)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(isOutgoing ? Color.white.opacity(0.82) : VoxiiTheme.muted)
                    .lineLimit(1)
            } else if let file = reply.file {
                Text("📎 \(file.filename)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(isOutgoing ? Color.white.opacity(0.82) : VoxiiTheme.muted)
                    .lineLimit(1)
            } else if replyVoiceURL != nil {
                Text("🎤 Voice message")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(isOutgoing ? Color.white.opacity(0.82) : VoxiiTheme.muted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(inlinePanelBackground(cornerRadius: 12))
    }

    private func fileBlock(_ file: APIFileAttachment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if isAudioAttachment(file), let fileURL {
                VoiceMessagePlayerView(url: fileURL, isOutgoing: isOutgoing)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: iconForFile(file))
                        .foregroundStyle(isOutgoing ? Color.white.opacity(0.9) : VoxiiTheme.accentLight)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.filename)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(isOutgoing ? .white : VoxiiTheme.text)
                            .lineLimit(1)

                        if let size = file.size {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(isOutgoing ? Color.white.opacity(0.78) : VoxiiTheme.muted)
                        }
                    }

                    Spacer()

                    if let fileURL {
                        Button("Open") {
                            onOpenFile(fileURL)
                        }
                        .buttonStyle(VoxiiGradientButtonStyle(isCompact: true, variant: .neutral))
                    }
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(inlinePanelBackground(cornerRadius: 14))
    }

    private func fallbackVoiceBlock(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VoiceMessagePlayerView(url: url, isOutgoing: isOutgoing)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(inlinePanelBackground(cornerRadius: 14))
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
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(reactedByCurrentUser(reaction) ? VoxiiTheme.accent.opacity(0.32) : Color.white.opacity(isOutgoing ? 0.12 : 0.07))
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(isOutgoing ? 0.24 : 0.12), lineWidth: 0.8)
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
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(isOutgoing ? 0.14 : 0.08))
                        )
                }
            }
        }
    }

    private var actionSection: some View {
        HStack(spacing: 10) {
            Button("Reply") {
                onReply()
            }
            .buttonStyle(VoxiiGradientButtonStyle(isCompact: true, variant: .neutral))

            if isOutgoing {
                Button("Edit") {
                    onEdit()
                }
                .buttonStyle(VoxiiGradientButtonStyle(isCompact: true, variant: .neutral))

                Button("Delete") {
                    onDelete()
                }
                .buttonStyle(VoxiiGradientButtonStyle(isCompact: true, variant: .danger))
            }
        }
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

    private var bubbleCornerRadius: CGFloat {
        VoxiiTheme.radiusM + 2
    }

    private var bubbleFillStyle: AnyShapeStyle {
        if isOutgoing {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        VoxiiTheme.accent.opacity(0.96),
                        VoxiiTheme.accentBlue.opacity(0.9)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    VoxiiTheme.glassStrong.opacity(0.78),
                    VoxiiTheme.glass.opacity(0.62),
                    VoxiiTheme.glassSoft.opacity(0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var bubbleGlossStyle: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(isOutgoing ? 0.22 : 0.14),
                Color.white.opacity(isOutgoing ? 0.08 : 0.04),
                .clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var bubbleStrokeStyle: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(isOutgoing ? 0.32 : 0.2),
                Color.white.opacity(isOutgoing ? 0.12 : 0.07)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var bubbleShadowColor: Color {
        (isOutgoing ? VoxiiTheme.accent : .black).opacity(isOutgoing ? 0.18 : 0.16)
    }

    private func inlinePanelBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isOutgoing ? 0.18 : 0.09),
                        Color.white.opacity(isOutgoing ? 0.1 : 0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(isOutgoing ? 0.26 : 0.12), lineWidth: 0.8)
            )
    }
}

private struct VoiceMessagePlayerView: View {
    let url: URL
    let isOutgoing: Bool

    @StateObject private var player: VoiceMessagePlayerModel
    @State private var isEditingProgress = false
    @State private var draftProgress = 0.0

    init(url: URL, isOutgoing: Bool) {
        self.url = url
        self.isOutgoing = isOutgoing
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
                    Text("Voice message")
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
                    self.errorText = item.error?.localizedDescription ?? "Cannot play this voice message."
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
            Button("Hide preview") {
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
        normalized(metadata.flatMap { $0.siteName }) ?? URL(string: urlString)?.host ?? "Link"
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
    @Published var statusText = "Connecting..."
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
            errorMessage = payload["message"] as? String ?? "Video call error."
        case "ended":
            state = .ended
        default:
            break
        }
    }

    private func run(_ script: String) {
        webView?.evaluateJavaScript(script)
    }
}

@MainActor
private final class VoxiiRingtonePlayer {
    static let shared = VoxiiRingtonePlayer()

    private var audioPlayer: AVAudioPlayer?
    private var isActive = false
    private static let generatedRingtoneFilename = "voxii_ringtone.wav"

    private init() {}

    func startIfNeeded() {
        guard !isActive else {
            return
        }

        do {
            let url = try Self.ringtoneFileURL()
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

    func stopIfNeeded() {
        guard isActive else {
            return
        }
        audioPlayer?.stop()
        audioPlayer = nil
        isActive = false
    }

    private static func ringtoneFileURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
        let fileURL = directory.appendingPathComponent(generatedRingtoneFilename)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let wavData = makeRingtoneWAV(sampleRate: 22_050)
            try wavData.write(to: fileURL, options: .atomic)
        }

        return fileURL
    }

    private static func makeRingtoneWAV(sampleRate: Int) -> Data {
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

    let config: VideoCallConfig
    let onClose: () -> Void

    @StateObject private var controller = VideoCallController()
    @State private var isAcceptingIncoming = false
    @State private var didAutoAcceptIncoming = false

    var body: some View {
        ZStack {
            VoxiiBackground()

            VideoCallWebContainer(config: config, controller: controller)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(VoxiiTheme.stroke, lineWidth: 1)
                )
                .padding(.horizontal, 14)
                .padding(.top, 68)
                .padding(.bottom, 148)

            if !controller.hasRemoteVideo && controller.state != .ended {
                VStack(spacing: 10) {
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(VoxiiTheme.muted)
                    Text(placeholderText)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(VoxiiTheme.muted)
                }
                .padding(.top, 34)
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                controlsBar
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if controller.state == .incoming {
                incomingOverlay
            }
        }
        .ignoresSafeArea()
        .onAppear {
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
        .alert("Call Error", isPresented: Binding(
            get: { controller.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    controller.errorMessage = nil
                }
            }
        )) {
            Button("Close", role: .cancel) {
                controller.endCall()
            }
        } message: {
            Text(controller.errorMessage ?? "Unknown error")
        }
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
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(VoxiiGradientButtonStyle(isCompact: true, variant: .neutral))

            VoxiiAvatarView(
                text: config.peer.avatar ?? config.peer.username,
                isOnline: true,
                size: 34
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(config.peer.username)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(VoxiiTheme.text)
                Text(controller.statusText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(VoxiiTheme.muted)
                    .lineLimit(1)
            }

            Spacer()

            Text("Video")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(VoxiiTheme.accentGradient)
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(VoxiiTheme.glassStrong)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(VoxiiTheme.stroke, lineWidth: 1)
        )
    }

    private var controlsBar: some View {
        HStack(spacing: 16) {
            callButton(
                icon: controller.isAudioEnabled ? "mic.fill" : "mic.slash.fill",
                active: controller.isAudioEnabled,
                action: { controller.toggleAudio() }
            )

            callButton(
                icon: controller.isVideoEnabled ? "video.fill" : "video.slash.fill",
                active: controller.isVideoEnabled,
                action: { controller.toggleVideo() }
            )

            Button {
                controller.endCall()
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 20, weight: .bold))
            }
            .buttonStyle(
                VoxiiRoundButtonStyle(
                    diameter: 68,
                    variant: .danger,
                    foregroundColor: .white
                )
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(VoxiiTheme.glassStrong)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(VoxiiTheme.stroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 8)
    }

    private var incomingOverlay: some View {
        VStack(spacing: 14) {
            Text("Incoming Video Call")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(VoxiiTheme.text)

            Text(controller.incomingCallerName ?? config.peer.username)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(VoxiiTheme.muted)

            HStack(spacing: 14) {
                Button("Decline") {
                    VoxiiRingtonePlayer.shared.stopIfNeeded()
                    controller.rejectIncoming()
                }
                .buttonStyle(VoxiiGradientButtonStyle(variant: .danger))

                Button {
                    Task { await acceptIncomingWithPermissions() }
                } label: {
                    if isAcceptingIncoming {
                        ProgressView()
                            .tint(.white)
                            .frame(minWidth: 76, minHeight: 20)
                    } else {
                        Text("Accept")
                    }
                }
                .buttonStyle(VoxiiGradientButtonStyle())
                .disabled(isAcceptingIncoming)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(VoxiiTheme.glassStrong)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(VoxiiTheme.stroke, lineWidth: 1)
        )
        .padding(.horizontal, 28)
    }

    private var placeholderText: String {
        switch controller.state {
        case .connecting:
            return "Connecting to call engine..."
        case .calling:
            return "Calling \(config.peer.username)..."
        case .incoming:
            return "Incoming call..."
        case .connected:
            return "Waiting for remote video..."
        case .ended:
            return "Call ended"
        }
    }

    private func callButton(icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
        }
        .buttonStyle(
            VoxiiRoundButtonStyle(
                diameter: 54,
                variant: active ? .accent : .neutral,
                foregroundColor: .white
            )
        )
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
            controller.errorMessage = "Microphone access is required for calls. Enable it in iOS Settings."
            return
        }

        let isAudioOnlyCall = config.callType.lowercased() == "audio"
        if !isAudioOnlyCall {
            let cameraGranted = await requestCameraPermission()
            guard cameraGranted else {
                controller.errorMessage = "Camera access is required for video calls. Enable it in iOS Settings."
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
                selfUsername: config.selfUser?.username ?? "Unknown",
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
    }
}
