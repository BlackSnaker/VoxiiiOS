import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif

enum VoxiiLanguage: String, CaseIterable, Identifiable {
    case ru
    case en

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ru:
            return "RU"
        case .en:
            return "EN"
        }
    }
}

enum VoxiiThemeName: String, CaseIterable, Identifiable {
    case `default`
    case midnight
    case forest
    case sunset
    case ocean
    case coffee

    var id: String { rawValue }
}

@MainActor
final class VoxiiAppearance: ObservableObject {
    static let shared = VoxiiAppearance()

    @Published var theme: VoxiiThemeName {
        didSet {
            defaults.set(theme.rawValue, forKey: Keys.theme)
            scheduleRefresh()
        }
    }

    @Published var accentHex: String {
        didSet {
            let normalized = Self.normalizeHex(accentHex) ?? Defaults.accentHex
            if accentHex != normalized {
                accentHex = normalized
                return
            }
            defaults.set(normalized, forKey: Keys.accentHex)
            scheduleRefresh()
        }
    }

    @Published var transparencyPercent: Double {
        didSet {
            let clamped = max(50, min(100, transparencyPercent.rounded()))
            if transparencyPercent != clamped {
                transparencyPercent = clamped
                return
            }
            defaults.set(clamped, forKey: Keys.transparencyPercent)
            scheduleRefresh()
        }
    }

    @Published var language: VoxiiLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            scheduleRefresh()
        }
    }

    @Published var linkPreviewEnabled: Bool {
        didSet {
            defaults.set(linkPreviewEnabled, forKey: Keys.linkPreviewEnabled)
        }
    }

    @Published private(set) var hiddenPreviews: Set<String> {
        didSet {
            defaults.set(Array(hiddenPreviews).sorted(), forKey: Keys.hiddenPreviews)
        }
    }

    @Published private(set) var refreshID = UUID()

    private let defaults = UserDefaults.standard
    private var refreshTask: Task<Void, Never>?

    fileprivate var palette: VoxiiPalette {
        VoxiiPalette(theme: theme, accentHex: accentHex, transparencyPercent: transparencyPercent)
    }

    var accentPresets: [String] {
        ["#8B5CF6", "#60A5FA", "#34D399", "#FBBF24", "#F87171", "#EC4899"]
    }

    init() {
        let savedTheme = VoxiiThemeName(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .default
        let savedAccent = Self.normalizeHex(defaults.string(forKey: Keys.accentHex)) ?? Defaults.accentHex

        let rawTransparency = defaults.double(forKey: Keys.transparencyPercent)
        let transparency = rawTransparency == 0 ? Defaults.transparencyPercent : rawTransparency

        let savedLanguage = VoxiiLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "")
            ?? VoxiiLanguage.fromPreferredLocale

        let hasStoredPreviewFlag = defaults.object(forKey: Keys.linkPreviewEnabled) != nil
        let previewEnabled = hasStoredPreviewFlag ? defaults.bool(forKey: Keys.linkPreviewEnabled) : true

        let hidden = Set(defaults.stringArray(forKey: Keys.hiddenPreviews) ?? [])

        theme = savedTheme
        accentHex = savedAccent
        transparencyPercent = max(50, min(100, transparency))
        language = savedLanguage
        linkPreviewEnabled = previewEnabled
        hiddenPreviews = hidden
    }

    deinit {
        refreshTask?.cancel()
    }

    func setAccent(hex: String) {
        accentHex = Self.normalizeHex(hex) ?? Defaults.accentHex
    }

    func setAccent(color: Color) {
        #if canImport(UIKit)
        if let hex = color.toHexString() {
            setAccent(hex: hex)
        }
        #endif
    }

    func isPreviewHidden(messageID: Int, urlString: String) -> Bool {
        hiddenPreviews.contains(previewKey(messageID: messageID, urlString: urlString))
    }

    func hidePreview(messageID: Int, urlString: String) {
        var next = hiddenPreviews
        next.insert(previewKey(messageID: messageID, urlString: urlString))
        hiddenPreviews = next
    }

    func resetHiddenPreviews() {
        hiddenPreviews = []
    }

    var hiddenPreviewCount: Int {
        hiddenPreviews.count
    }

    func t(_ key: String) -> String {
        let dict = Self.translations[language] ?? Self.translations[.en] ?? [:]
        return dict[key] ?? key
    }

    func tf(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), locale: translationLocale, arguments: arguments)
    }

    func statusLabel(_ rawValue: String?) -> String {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch trimmed.lowercased() {
        case "", "offline":
            return t("common.offline")
        case "online":
            return t("common.online")
        default:
            return trimmed
        }
    }

    func themeLabel(_ name: VoxiiThemeName) -> String {
        switch name {
        case .default:
            return t("theme.default")
        case .midnight:
            return t("theme.midnight")
        case .forest:
            return t("theme.forest")
        case .sunset:
            return t("theme.sunset")
        case .ocean:
            return t("theme.ocean")
        case .coffee:
            return t("theme.coffee")
        }
    }

    private static func normalizeHex(_ value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        if !value.hasPrefix("#") {
            value = "#\(value)"
        }

        let candidate = value.uppercased()
        guard candidate.count == 7 else {
            return nil
        }

        guard candidate.dropFirst().allSatisfy({ $0.isHexDigit }) else {
            return nil
        }

        return candidate
    }

    private func previewKey(messageID: Int, urlString: String) -> String {
        "\(messageID)-\(urlString)"
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled else {
                return
            }
            self?.refreshID = UUID()
        }
    }

    private var translationLocale: Locale {
        switch language {
        case .ru:
            return Locale(identifier: "ru_RU")
        case .en:
            return Locale(identifier: "en_US_POSIX")
        }
    }

    private enum Keys {
        static let theme = "voxii_theme"
        static let accentHex = "voxii_accent_hex"
        static let transparencyPercent = "voxii_transparency_percent"
        static let language = "voxii_language"
        static let linkPreviewEnabled = "voxii_link_preview_enabled"
        static let hiddenPreviews = "voxii_hidden_previews"
    }

    private enum Defaults {
        static let accentHex = "#8B5CF6"
        static let transparencyPercent = 86.0
    }

    private static let translations: [VoxiiLanguage: [String: String]] = [
        .en: [
            "common.accept": "Accept",
            "common.add": "Add",
            "common.apply": "Apply",
            "common.cancel": "Cancel",
            "common.change": "Change",
            "common.clear": "Clear",
            "common.close": "Close",
            "common.delete": "Delete",
            "common.edit": "Edit",
            "common.error": "Error",
            "common.friend": "Friend",
            "common.id": "ID",
            "common.link": "Link",
            "common.noEmail": "No email",
            "common.offline": "Offline",
            "common.ok": "OK",
            "common.online": "Online",
            "common.open": "Open",
            "common.reject": "Reject",
            "common.reply": "Reply",
            "common.requested": "Requested",
            "common.unknown": "Unknown",
            "common.unknownError": "Unknown error",
            "tab.messages": "Messages",
            "tab.friends": "Friends",
            "tab.news": "News",
            "tab.notifications": "Notifications",
            "tab.settings": "Settings",
            "auth.mode.login": "Login",
            "auth.mode.register": "Register",
            "auth.welcomeBack": "Welcome Back",
            "auth.createAccount": "Create Account",
            "auth.loginSubtitle": "Login to your Voxii messenger.",
            "auth.registerSubtitle": "Join Voxii and start chatting.",
            "auth.usernameLabel": "USERNAME",
            "auth.usernamePlaceholder": "Enter username",
            "auth.emailLabel": "EMAIL",
            "auth.passwordLabel": "PASSWORD",
            "auth.passwordPlaceholder": "At least 6 characters",
            "auth.submit.login": "Log In",
            "auth.submit.register": "Create Account",
            "auth.serverLabel": "SERVER",
            "server.title": "Voxii Server",
            "server.urlLabel": "SERVER URL",
            "server.testConnection": "Test Connection",
            "server.quickPresets": "QUICK PRESETS",
            "server.production": "Production Server",
            "server.localhost": "Localhost (Simulator)",
            "server.lanExample": "Example LAN Address",
            "server.notes": "NOTES",
            "server.note1": "Use 127.0.0.1 in iOS Simulator when Voxii backend runs on the same Mac.",
            "server.note2": "Default production server: https://voxii.lenuma.ru",
            "server.note3": "Use your production domain with a valid certificate for iPhone and App Store builds.",
            "server.note4": "For physical iPhone, use your Mac LAN IP and ensure both devices are in one network.",
            "server.note5": "If scheme is omitted, Voxii tries HTTPS first and then HTTP.",
            "server.note6": "For production domains, HTTPS is recommended.",
            "server.connected": "Connected successfully.",
            "server.reachable": "Server is reachable.",
            "dm.title": "Direct Messages",
            "dm.searchPlaceholder": "Find or start a conversation",
            "dm.loading": "Loading conversations...",
            "dm.noMatches": "No matching users",
            "dm.tryAnotherSearch": "Try another search query.",
            "friends.title": "Friends",
            "friends.subtitle": "Manage online, pending and new requests",
            "friends.segmentTitle": "Friends",
            "friends.tab.online": "Online",
            "friends.tab.all": "All",
            "friends.tab.pending": "Pending",
            "friends.tab.add": "Add Friend",
            "friends.noOnline": "No friends online",
            "friends.noFriends": "No friends yet",
            "friends.noPending": "No pending requests",
            "friends.searchPlaceholder": "Search username",
            "friends.searchHint": "Type username to find users",
            "news.title": "News",
            "news.empty": "No news messages yet",
            "news.readOnly": "News channel is read-only",
            "news.system": "System",
            "news.subscribers": "%d subscribers",
            "news.systemChannel": "System channel",
            "news.edited": "(edited)",
            "news.attachmentPlaceholder": "[attachment]",
            "news.notFound": "System channel not found.",
            "notifications.title": "Notifications",
            "notifications.unreadCount": "%d unread",
            "notifications.allCaughtUp": "All caught up",
            "notifications.readAll": "Read all",
            "notifications.loading": "Loading notifications...",
            "notifications.empty": "No notifications",
            "notifications.markRead": "Mark read",
            "notifications.missedVoice": "Missed voice call",
            "notifications.missedVideo": "Missed video call",
            "push.newMessage": "You have a new message",
            "chat.deletePrompt": "Delete message?",
            "chat.editing": "Editing message",
            "chat.replyingTo": "Replying to %@",
            "chat.messagePlaceholder": "Message",
            "chat.updatePlaceholder": "Update message",
            "chat.transcribe": "Transcribe",
            "chat.recording": "Recording voice message...",
            "chat.stop": "Stop",
            "chat.emptyTitle": "No messages yet",
            "chat.emptySubtitle": "Start the conversation with %@.",
            "chat.attachment": "Attachment: %@",
            "chat.voiceMessage": "Voice message",
            "chat.noText": "No text",
            "chat.edited": "edited",
            "chat.replyAuthor": "↪ %@",
            "chat.attachmentInline": "📎 %@",
            "chat.voiceInline": "🎤 Voice message",
            "chat.hidePreview": "Hide preview",
            "chat.messageEmpty": "Message cannot be empty.",
            "chat.uploadVoiceFailed": "Failed to upload voice message.",
            "chat.fileTooLarge": "File is too large. Maximum size is 10MB.",
            "chat.voiceWhileEditing": "Voice recording is disabled while editing a message.",
            "chat.removeAttachmentFirst": "Remove current attachment before recording.",
            "chat.microphoneDenied": "Microphone access denied. Enable it in iOS Settings.",
            "chat.voiceStartFailed": "Unable to start voice recording.",
            "chat.voiceTooShort": "Voice message is too short.",
            "chat.voiceFileMissing": "Recorded file not found.",
            "chat.voiceTooLarge": "Voice message is too large. Maximum size is 10MB.",
            "chat.noSpeechDetected": "No speech detected in selected audio.",
            "chat.voicePlaybackError": "Cannot play this voice message.",
            "call.errorTitle": "Call Error",
            "call.video": "Video",
            "call.incomingVideo": "Incoming Video Call",
            "call.decline": "Decline",
            "call.accept": "Accept",
            "call.connectingShort": "Connecting...",
            "call.connectingEngine": "Connecting to call engine...",
            "call.callingUser": "Calling %@...",
            "call.incoming": "Incoming call...",
            "call.waitingRemoteVideo": "Waiting for remote video...",
            "call.ended": "Call ended",
            "call.microphoneRequired": "Microphone access is required for calls. Enable it in iOS Settings.",
            "call.cameraRequired": "Camera access is required for video calls. Enable it in iOS Settings.",
            "call.videoError": "Video call error.",
            "settings.title": "Settings",
            "settings.subtitle": "Profile, visual style, privacy and connection in one place.",
            "settings.appearance": "Appearance",
            "settings.appearanceSubtitle": "Language, theme and visual effects",
            "settings.language": "Language",
            "settings.theme": "Theme",
            "settings.accent": "Accent Color",
            "settings.glass": "Glass Effect",
            "settings.privacy": "Privacy & Content",
            "settings.privacySubtitle": "Control previews and content visibility",
            "settings.linkPreview": "Link Previews",
            "settings.linkPreviewDesc": "Show preview cards for links in messages",
            "settings.resetHidden": "Reset Hidden Previews",
            "settings.hiddenCount": "Hidden previews",
            "settings.server": "Server",
            "settings.serverSubtitle": "Current backend and connection options",
            "settings.changeServer": "Change",
            "settings.serverHint": "Use 127.0.0.1 in simulator and LAN IP on physical iPhone.",
            "settings.account": "Account",
            "settings.accountSubtitle": "Session and account actions",
            "settings.signOutHint": "You can sign out from this device at any time.",
            "settings.signOut": "Sign Out",
            "settings.signingOut": "Signing out...",
            "theme.default": "Default Dark",
            "theme.midnight": "Midnight Blue",
            "theme.forest": "Forest Green",
            "theme.sunset": "Sunset Purple",
            "theme.ocean": "Ocean Blue",
            "theme.coffee": "Coffee Brown"
        ],
        .ru: [
            "common.accept": "Принять",
            "common.add": "Добавить",
            "common.apply": "Применить",
            "common.cancel": "Отмена",
            "common.change": "Изменить",
            "common.clear": "Очистить",
            "common.close": "Закрыть",
            "common.delete": "Удалить",
            "common.edit": "Изменить",
            "common.error": "Ошибка",
            "common.friend": "Друг",
            "common.id": "ID",
            "common.link": "Ссылка",
            "common.noEmail": "Нет email",
            "common.offline": "Не в сети",
            "common.ok": "OK",
            "common.online": "В сети",
            "common.open": "Открыть",
            "common.reject": "Отклонить",
            "common.reply": "Ответить",
            "common.requested": "Запрошено",
            "common.unknown": "Неизвестно",
            "common.unknownError": "Неизвестная ошибка",
            "tab.messages": "Сообщения",
            "tab.friends": "Друзья",
            "tab.news": "Новости",
            "tab.notifications": "Уведомления",
            "tab.settings": "Настройки",
            "auth.mode.login": "Вход",
            "auth.mode.register": "Регистрация",
            "auth.welcomeBack": "С возвращением",
            "auth.createAccount": "Создать аккаунт",
            "auth.loginSubtitle": "Войдите в мессенджер Voxii.",
            "auth.registerSubtitle": "Присоединяйтесь к Voxii и начните общение.",
            "auth.usernameLabel": "ИМЯ ПОЛЬЗОВАТЕЛЯ",
            "auth.usernamePlaceholder": "Введите имя пользователя",
            "auth.emailLabel": "EMAIL",
            "auth.passwordLabel": "ПАРОЛЬ",
            "auth.passwordPlaceholder": "Минимум 6 символов",
            "auth.submit.login": "Войти",
            "auth.submit.register": "Создать аккаунт",
            "auth.serverLabel": "СЕРВЕР",
            "server.title": "Сервер Voxii",
            "server.urlLabel": "URL СЕРВЕРА",
            "server.testConnection": "Проверить соединение",
            "server.quickPresets": "БЫСТРЫЕ ШАБЛОНЫ",
            "server.production": "Продакшн-сервер",
            "server.localhost": "Localhost (Симулятор)",
            "server.lanExample": "Пример LAN-адреса",
            "server.notes": "ПРИМЕЧАНИЯ",
            "server.note1": "Используйте 127.0.0.1 в iOS Simulator, когда сервер Voxii запущен на этом же Mac.",
            "server.note2": "Продакшн-сервер по умолчанию: https://voxii.lenuma.ru",
            "server.note3": "Для iPhone и App Store сборок используйте продакшн-домен с валидным сертификатом.",
            "server.note4": "Для физического iPhone используйте LAN IP вашего Mac и убедитесь, что оба устройства в одной сети.",
            "server.note5": "Если схема не указана, Voxii сначала попробует HTTPS, затем HTTP.",
            "server.note6": "Для продакшн-доменов рекомендуется HTTPS.",
            "server.connected": "Соединение успешно установлено.",
            "server.reachable": "Сервер доступен.",
            "dm.title": "Личные сообщения",
            "dm.searchPlaceholder": "Найти или начать диалог",
            "dm.loading": "Загрузка диалогов...",
            "dm.noMatches": "Пользователи не найдены",
            "dm.tryAnotherSearch": "Попробуйте другой поисковый запрос.",
            "friends.title": "Друзья",
            "friends.subtitle": "Управляйте друзьями, заявками и новыми контактами",
            "friends.segmentTitle": "Друзья",
            "friends.tab.online": "Онлайн",
            "friends.tab.all": "Все",
            "friends.tab.pending": "Входящие",
            "friends.tab.add": "Добавить друга",
            "friends.noOnline": "Нет друзей онлайн",
            "friends.noFriends": "Пока нет друзей",
            "friends.noPending": "Нет входящих заявок",
            "friends.searchPlaceholder": "Поиск по имени",
            "friends.searchHint": "Введите имя пользователя для поиска",
            "news.title": "Новости",
            "news.empty": "Пока нет новостей",
            "news.readOnly": "Канал новостей доступен только для чтения",
            "news.system": "Система",
            "news.subscribers": "%d подписчиков",
            "news.systemChannel": "Системный канал",
            "news.edited": "(изменено)",
            "news.attachmentPlaceholder": "[вложение]",
            "news.notFound": "Системный канал не найден.",
            "notifications.title": "Уведомления",
            "notifications.unreadCount": "%d непрочитанных",
            "notifications.allCaughtUp": "Всё прочитано",
            "notifications.readAll": "Прочитать всё",
            "notifications.loading": "Загрузка уведомлений...",
            "notifications.empty": "Нет уведомлений",
            "notifications.markRead": "Прочитать",
            "notifications.missedVoice": "Пропущенный голосовой звонок",
            "notifications.missedVideo": "Пропущенный видеозвонок",
            "push.newMessage": "У вас новое сообщение",
            "chat.deletePrompt": "Удалить сообщение?",
            "chat.editing": "Редактирование сообщения",
            "chat.replyingTo": "Ответ для %@",
            "chat.messagePlaceholder": "Сообщение",
            "chat.updatePlaceholder": "Изменить сообщение",
            "chat.transcribe": "Расшифровать",
            "chat.recording": "Идёт запись голосового сообщения...",
            "chat.stop": "Стоп",
            "chat.emptyTitle": "Сообщений пока нет",
            "chat.emptySubtitle": "Начните диалог с %@.",
            "chat.attachment": "Вложение: %@",
            "chat.voiceMessage": "Голосовое сообщение",
            "chat.noText": "Нет текста",
            "chat.edited": "изменено",
            "chat.replyAuthor": "↪ %@",
            "chat.attachmentInline": "📎 %@",
            "chat.voiceInline": "🎤 Голосовое сообщение",
            "chat.hidePreview": "Скрыть превью",
            "chat.messageEmpty": "Сообщение не может быть пустым.",
            "chat.uploadVoiceFailed": "Не удалось загрузить голосовое сообщение.",
            "chat.fileTooLarge": "Файл слишком большой. Максимальный размер — 10 МБ.",
            "chat.voiceWhileEditing": "Во время редактирования запись голосового недоступна.",
            "chat.removeAttachmentFirst": "Сначала удалите текущее вложение.",
            "chat.microphoneDenied": "Доступ к микрофону запрещён. Включите его в настройках iOS.",
            "chat.voiceStartFailed": "Не удалось начать запись голосового сообщения.",
            "chat.voiceTooShort": "Голосовое сообщение слишком короткое.",
            "chat.voiceFileMissing": "Записанный файл не найден.",
            "chat.voiceTooLarge": "Голосовое сообщение слишком большое. Максимальный размер — 10 МБ.",
            "chat.noSpeechDetected": "В выбранном аудио речь не обнаружена.",
            "chat.voicePlaybackError": "Не удалось воспроизвести голосовое сообщение.",
            "call.errorTitle": "Ошибка звонка",
            "call.video": "Видео",
            "call.incomingVideo": "Входящий видеозвонок",
            "call.decline": "Отклонить",
            "call.accept": "Принять",
            "call.connectingShort": "Подключение...",
            "call.connectingEngine": "Подключение к звонку...",
            "call.callingUser": "Звоним %@...",
            "call.incoming": "Входящий звонок...",
            "call.waitingRemoteVideo": "Ожидание видео собеседника...",
            "call.ended": "Звонок завершён",
            "call.microphoneRequired": "Для звонков нужен доступ к микрофону. Разрешите его в настройках iOS.",
            "call.cameraRequired": "Для видеозвонков нужен доступ к камере. Разрешите его в настройках iOS.",
            "call.videoError": "Ошибка видеозвонка.",
            "settings.title": "Настройки",
            "settings.subtitle": "Профиль, внешний вид, приватность и подключение в одном месте.",
            "settings.appearance": "Внешний вид",
            "settings.appearanceSubtitle": "Язык, тема и визуальные эффекты",
            "settings.language": "Язык",
            "settings.theme": "Тема",
            "settings.accent": "Акцентный цвет",
            "settings.glass": "Эффект стекла",
            "settings.privacy": "Приватность и контент",
            "settings.privacySubtitle": "Управление превью и видимостью контента",
            "settings.linkPreview": "Превью ссылок",
            "settings.linkPreviewDesc": "Показывать карточки ссылок в сообщениях",
            "settings.resetHidden": "Сбросить скрытые превью",
            "settings.hiddenCount": "Скрытых превью",
            "settings.server": "Сервер",
            "settings.serverSubtitle": "Текущий сервер и параметры подключения",
            "settings.changeServer": "Изменить",
            "settings.serverHint": "В симуляторе используйте 127.0.0.1, на iPhone — LAN IP вашего Mac.",
            "settings.account": "Аккаунт",
            "settings.accountSubtitle": "Действия с сессией и аккаунтом",
            "settings.signOutHint": "Вы можете выйти из аккаунта на этом устройстве в любой момент.",
            "settings.signOut": "Выйти",
            "settings.signingOut": "Выход...",
            "theme.default": "Стандартная тёмная",
            "theme.midnight": "Полночная синяя",
            "theme.forest": "Лесная зелёная",
            "theme.sunset": "Фиолетовый закат",
            "theme.ocean": "Океанская синяя",
            "theme.coffee": "Кофейная коричневая"
        ]
    ]
}

private extension VoxiiLanguage {
    static var fromPreferredLocale: VoxiiLanguage {
        let code = Locale.current.language.languageCode?.identifier.lowercased() ?? ""
        return code == "ru" ? .ru : .en
    }
}

private struct VoxiiPalette {
    let theme: VoxiiThemeName
    let accentHex: String
    let transparencyPercent: Double

    private var themeSpec: ThemeSpec {
        switch theme {
        case .default:
            return ThemeSpec(bg0: "#0A0F18", bg1: "#0C1322", glassR: 16, glassG: 20, glassB: 30)
        case .midnight:
            return ThemeSpec(bg0: "#0A0A1A", bg1: "#121226", glassR: 10, glassG: 10, glassB: 26)
        case .forest:
            return ThemeSpec(bg0: "#0A1A10", bg1: "#0F2A1F", glassR: 15, glassG: 42, glassB: 31)
        case .sunset:
            return ThemeSpec(bg0: "#1A0A1A", bg1: "#261212", glassR: 38, glassG: 18, glassB: 26)
        case .ocean:
            return ThemeSpec(bg0: "#0A1A26", bg1: "#122626", glassR: 18, glassG: 38, glassB: 38)
        case .coffee:
            return ThemeSpec(bg0: "#261C14", bg1: "#3C2A1F", glassR: 60, glassG: 42, glassB: 31)
        }
    }

    private var accentRGB: RGBColor {
        RGBColor(hex: accentHex) ?? RGBColor(hex: "#8B5CF6") ?? RGBColor(r: 0.545, g: 0.361, b: 0.965)
    }

    private var opacity: Double {
        max(0.5, min(1, transparencyPercent / 100))
    }

    var bg0: Color { Color(hex: themeSpec.bg0) ?? Color(.sRGB, red: 10 / 255, green: 15 / 255, blue: 24 / 255, opacity: 1) }
    var bg1: Color { Color(hex: themeSpec.bg1) ?? Color(.sRGB, red: 12 / 255, green: 19 / 255, blue: 34 / 255, opacity: 1) }

    var glass: Color {
        Color(
            .sRGB,
            red: themeSpec.glassR / 255,
            green: themeSpec.glassG / 255,
            blue: themeSpec.glassB / 255,
            opacity: opacity
        )
    }

    var glassSoft: Color {
        Color(
            .sRGB,
            red: themeSpec.glassR / 255,
            green: themeSpec.glassG / 255,
            blue: themeSpec.glassB / 255,
            opacity: max(0.1, opacity - 0.1)
        )
    }

    var glassStrong: Color {
        Color(
            .sRGB,
            red: themeSpec.glassR / 255,
            green: themeSpec.glassG / 255,
            blue: themeSpec.glassB / 255,
            opacity: min(0.98, opacity + 0.06)
        )
    }

    var stroke: Color { Color.white.opacity(0.08) }
    var text: Color { Color.white.opacity(0.92) }
    var muted: Color { Color.white.opacity(0.62) }
    var mutedSecondary: Color { Color.white.opacity(0.48) }

    var accent: Color { accentRGB.color }
    var accentBlue: Color { accentRGB.lighten(20).color }
    var accentLight: Color { accentRGB.lighten(60).color }

    var online: Color { Color(hex: "#22C55E") ?? .green }
    var danger: Color { Color(hex: "#EF4444") ?? .red }

    struct ThemeSpec {
        let bg0: String
        let bg1: String
        let glassR: Double
        let glassG: Double
        let glassB: Double
    }
}

private struct RGBColor {
    let r: Double
    let g: Double
    let b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = max(0, min(1, r))
        self.g = max(0, min(1, g))
        self.b = max(0, min(1, b))
    }

    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        guard value.count == 6, let intValue = Int(value, radix: 16) else {
            return nil
        }

        self.init(
            r: Double((intValue >> 16) & 0xFF) / 255,
            g: Double((intValue >> 8) & 0xFF) / 255,
            b: Double(intValue & 0xFF) / 255
        )
    }

    var color: Color {
        Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    func lighten(_ percent: Double) -> RGBColor {
        let clamped = max(0, min(1, percent / 100))
        return RGBColor(
            r: r + (1 - r) * clamped,
            g: g + (1 - g) * clamped,
            b: b + (1 - b) * clamped
        )
    }
}

enum VoxiiTheme {
    private static var palette: VoxiiPalette {
        VoxiiAppearance.shared.palette
    }

    static var bg0: Color { palette.bg0 }
    static var bg1: Color { palette.bg1 }
    static var glass: Color { palette.glass }
    static var glassSoft: Color { palette.glassSoft }
    static var glassStrong: Color { palette.glassStrong }
    static var stroke: Color { palette.stroke }
    static var text: Color { palette.text }
    static var muted: Color { palette.muted }
    static var mutedSecondary: Color { palette.mutedSecondary }

    static var accent: Color { palette.accent }
    static var accentBlue: Color { palette.accentBlue }
    static var accentLight: Color { palette.accentLight }
    static var online: Color { palette.online }
    static var danger: Color { palette.danger }

    static var backgroundGradient: LinearGradient {
        LinearGradient(colors: [bg0, bg1], startPoint: .top, endPoint: .bottom)
    }

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accentBlue, accent, accentLight.opacity(0.86)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static let radiusS: CGFloat = 18
    static let radiusM: CGFloat = 24
    static let radiusL: CGFloat = 30
    static let radiusXL: CGFloat = 38

    static let controlHeightCompact: CGFloat = 42
    static let controlHeightRegular: CGFloat = 54
}

struct VoxiiBackground: View {
    var body: some View {
        ZStack {
            VoxiiTheme.backgroundGradient

            RadialGradient(
                colors: [VoxiiTheme.accent.opacity(0.16), .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 360
            )
            .scaleEffect(1.1)
            .offset(x: -120, y: -220)

            RadialGradient(
                colors: [VoxiiTheme.accentBlue.opacity(0.12), .clear],
                center: .topTrailing,
                startRadius: 14,
                endRadius: 340
            )
            .scaleEffect(1.06)
            .offset(x: 120, y: -180)

            RadialGradient(
                colors: [VoxiiTheme.online.opacity(0.08), .clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 320
            )
            .offset(x: 90, y: 220)

            LinearGradient(
                colors: [Color.white.opacity(0.03), .clear, Color.black.opacity(0.11)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.screen)

            Circle()
                .fill(VoxiiTheme.accent.opacity(0.04))
                .frame(width: 320, height: 320)
                .blur(radius: 38)
                .offset(x: 130, y: -260)

            Circle()
                .fill(VoxiiTheme.accentBlue.opacity(0.03))
                .frame(width: 280, height: 280)
                .blur(radius: 34)
                .offset(x: -150, y: 290)
        }
        .ignoresSafeArea()
    }
}

struct VoxiiCardModifier: ViewModifier {
    var cornerRadius: CGFloat = VoxiiTheme.radiusL
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                VoxiiTheme.glassStrong.opacity(0.64),
                                VoxiiTheme.glassSoft.opacity(0.6),
                                Color.white.opacity(0.03)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(VoxiiTheme.stroke.opacity(0.95), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.2), Color.white.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.1
                    )
            )
            .shadow(color: .black.opacity(0.14), radius: 8, x: 0, y: 5)
    }
}

extension View {
    func voxiiCard(cornerRadius: CGFloat = VoxiiTheme.radiusL, padding: CGFloat = 14) -> some View {
        modifier(VoxiiCardModifier(cornerRadius: cornerRadius, padding: padding))
    }
}

struct VoxiiInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(VoxiiTheme.text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(minHeight: VoxiiTheme.controlHeightRegular)
            .background(
                RoundedRectangle(cornerRadius: VoxiiTheme.radiusM, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.1),
                                VoxiiTheme.glass.opacity(0.46),
                                Color.black.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: VoxiiTheme.radiusM, style: .continuous)
                    .stroke(VoxiiTheme.stroke.opacity(0.9), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: VoxiiTheme.radiusM, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.14), Color.white.opacity(0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }
}

extension View {
    func voxiiInput() -> some View {
        modifier(VoxiiInputModifier())
    }
}

struct VoxiiGradientButtonStyle: ButtonStyle {
    var isCompact = false
    var variant: VoxiiButtonVariant = .accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let radius = isCompact ? VoxiiTheme.radiusM : VoxiiTheme.radiusL
        let minHeight = isCompact ? VoxiiTheme.controlHeightCompact : VoxiiTheme.controlHeightRegular
        let pressed = configuration.isPressed

        configuration.label
            .font(.system(size: isCompact ? 14 : 15, weight: .bold, design: .rounded))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, isCompact ? 16 : 22)
            .padding(.vertical, isCompact ? 9 : 12)
            .frame(minHeight: minHeight)
            .background(
                ZStack {
                    if usesBaseMaterial {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(.thinMaterial)
                    }

                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(backgroundShapeStyle)

                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.2), Color.white.opacity(0.03), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.screen)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: max(6, radius - 2), style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.4)
            )
            .scaleEffect(pressed ? 0.965 : 1)
            .offset(y: pressed ? 1.4 : 0)
            .brightness(pressed ? -0.03 : 0)
            .shadow(
                color: shadowAccentColor.opacity(pressed ? 0.1 : 0.16),
                radius: pressed ? 4 : 8,
                x: 0,
                y: pressed ? 2 : 5
            )
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.72), value: pressed)
    }

    private var foregroundColor: Color {
        switch variant {
        case .accent, .danger:
            return .white
        case .neutral:
            return VoxiiTheme.text
        }
    }

    private var backgroundShapeStyle: AnyShapeStyle {
        switch variant {
        case .accent:
            return AnyShapeStyle(VoxiiTheme.accentGradient)
        case .neutral:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.1),
                        VoxiiTheme.glass.opacity(0.5),
                        Color.black.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .danger:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        VoxiiTheme.danger.opacity(0.95),
                        Color(hex: "#F97316") ?? .orange
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    private var borderColor: Color {
        switch variant {
        case .accent, .danger:
            return Color.white.opacity(0.12)
        case .neutral:
            return VoxiiTheme.stroke.opacity(0.95)
        }
    }

    private var shadowAccentColor: Color {
        switch variant {
        case .accent:
            return VoxiiTheme.accent
        case .neutral:
            return VoxiiTheme.accentBlue
        case .danger:
            return VoxiiTheme.danger
        }
    }

    private var usesBaseMaterial: Bool {
        variant != .neutral
    }
}

struct VoxiiRoundButtonStyle: ButtonStyle {
    var diameter: CGFloat = 46
    var variant: VoxiiButtonVariant = .accent
    var foregroundColor: Color? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed

        configuration.label
            .foregroundStyle(foregroundColor ?? defaultForegroundColor)
            .frame(width: diameter, height: diameter)
            .background(
                ZStack {
                    if usesBaseMaterial {
                        Circle()
                            .fill(.thinMaterial)
                    }

                    Circle()
                        .fill(backgroundShapeStyle)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.18), Color.white.opacity(0.03), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.screen)
                }
            )
            .overlay(
                Circle()
                    .stroke(borderColor, lineWidth: 1)
            )
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.4)
            )
            .scaleEffect(pressed ? 0.955 : 1)
            .offset(y: pressed ? 1.2 : 0)
            .brightness(pressed ? -0.03 : 0)
            .shadow(
                color: shadowAccentColor.opacity(pressed ? 0.09 : 0.14),
                radius: pressed ? 4 : 8,
                x: 0,
                y: pressed ? 2 : 4
            )
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72), value: pressed)
    }

    private var defaultForegroundColor: Color {
        switch variant {
        case .accent, .danger:
            return .white
        case .neutral:
            return VoxiiTheme.text
        }
    }

    private var backgroundShapeStyle: AnyShapeStyle {
        switch variant {
        case .accent:
            return AnyShapeStyle(VoxiiTheme.accentGradient)
        case .neutral:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.1),
                        VoxiiTheme.glass.opacity(0.5),
                        Color.black.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .danger:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        VoxiiTheme.danger.opacity(0.95),
                        Color(hex: "#F97316") ?? .orange
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    private var borderColor: Color {
        switch variant {
        case .accent, .danger:
            return Color.white.opacity(0.12)
        case .neutral:
            return VoxiiTheme.stroke.opacity(0.95)
        }
    }

    private var shadowAccentColor: Color {
        switch variant {
        case .accent:
            return VoxiiTheme.accent
        case .neutral:
            return VoxiiTheme.accentBlue
        case .danger:
            return VoxiiTheme.danger
        }
    }

    private var usesBaseMaterial: Bool {
        variant != .neutral
    }
}

enum VoxiiButtonVariant {
    case accent
    case neutral
    case danger
}

struct VoxiiAvatarView: View {
    let text: String
    let isOnline: Bool
    var size: CGFloat = 44

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(.thinMaterial)
                .overlay(
                    Circle()
                        .fill(VoxiiTheme.accentGradient)
                        .padding(2)
                )
                .frame(width: size, height: size)
                .overlay(
                    Text(avatarLetter)
                        .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                )
                .shadow(color: .black.opacity(0.2), radius: 7, x: 0, y: 4)

            Circle()
                .fill(isOnline ? VoxiiTheme.online : VoxiiTheme.mutedSecondary)
                .frame(width: max(10, size * 0.24), height: max(10, size * 0.24))
                .overlay(
                    Circle()
                        .stroke(VoxiiTheme.bg1, lineWidth: 2.4)
                )
        }
    }

    private var avatarLetter: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "V" : String(trimmed.prefix(1)).uppercased()
    }
}

extension Color {
    init?(hex: String) {
        guard let rgb = RGBColor(hex: hex) else {
            return nil
        }
        self = rgb.color
    }

    #if canImport(UIKit)
    func toHexString() -> String? {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }

        return String(
            format: "#%02X%02X%02X",
            Int(red * 255),
            Int(green * 255),
            Int(blue * 255)
        )
    }
    #endif
}

@MainActor
enum VoxiiSystemAppearance {
    static func apply() {
        #if canImport(UIKit)
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithTransparentBackground()
        tabAppearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        tabAppearance.backgroundColor = UIColor(VoxiiTheme.glassSoft).withAlphaComponent(0.44)
        tabAppearance.shadowColor = UIColor.white.withAlphaComponent(0.05)

        let normalColor = UIColor(VoxiiTheme.muted)
        let selectedColor = UIColor(VoxiiTheme.accentLight)
        let itemFont = UIFont.systemFont(ofSize: 11, weight: .semibold)

        for layout in [tabAppearance.stackedLayoutAppearance, tabAppearance.inlineLayoutAppearance, tabAppearance.compactInlineLayoutAppearance] {
            layout.normal.iconColor = normalColor
            layout.selected.iconColor = selectedColor
            layout.normal.titleTextAttributes = [.foregroundColor: normalColor, .font: itemFont]
            layout.selected.titleTextAttributes = [.foregroundColor: selectedColor, .font: itemFont]
        }

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithTransparentBackground()
        navigationAppearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        navigationAppearance.backgroundColor = UIColor.clear
        navigationAppearance.titleTextAttributes = [.foregroundColor: UIColor(VoxiiTheme.text)]
        navigationAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(VoxiiTheme.text)]

        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        UINavigationBar.appearance().compactAppearance = navigationAppearance
        #endif
    }
}
