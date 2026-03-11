# Project Diary / Дневник проекта

## RU

### О проекте
**Voxii iOS** — нативный iOS-клиент мессенджера Voxii, построенный на `SwiftUI`, с интеграцией с реальным сервером, чатом, голосовыми сообщениями, звонками, новостями, уведомлениями и системными функциями iPhone.

Этот файл фиксирует ключевые особенности, архитектурные решения и основные доработки, внесённые в проект.

### Архитектура и основные модули
- `SessionStore.swift` — сессия пользователя, токен, базовые API-действия, синхронизация состояния.
- `VoxiiAPIClient.swift` — HTTP-клиент для аутентификации, DM, друзей, уведомлений, профиля, загрузки файлов и транскрипции.
- `ChatView.swift` — основной интерфейс личного чата, отправка сообщений, вложений, голосовых, реакции, редактирование, ответы, звонки.
- `MessengerHomeView.swift` — вкладки `Сообщения`, `Друзья`, `Новости`, `Уведомления`, `Настройки`.
- `VoxiiSystemCalls.swift` — системная интеграция вызовов через `CallKit`, разбор входящих call/message payload.
- `VixiiApp.swift` — регистрация уведомлений, APNs/VoIP push handling, делегаты `UNUserNotificationCenter` и `PKPushRegistry`.
- `VoxiiTheme.swift` — тема, палитра, стеклянные слои, локализация интерфейса RU/EN.
- `VoxiiSocketDMClient.swift` — отправка DM через socket-слой для совместимости с веб-логикой сервера.

### Реализованные возможности

#### 1. Аутентификация и профиль
- Вход и регистрация в нативном iOS-интерфейсе.
- Поддержка серверной схемы входа, совместимой с веб-версией мессенджера.
- Работа с профилем текущего пользователя.

#### 2. Личные сообщения (DM)
- Отправка текстовых сообщений.
- Редактирование и удаление своих сообщений.
- Ответы на сообщения.
- Реакции на сообщения.
- Поддержка вложений и файлов.
- Отображение ссылок с предпросмотром.

#### 3. Голосовые сообщения
- Запись голосовых сообщений внутри приложения.
- Отправка голосовых так, чтобы они были совместимы с браузерной версией мессенджера.
- Воспроизведение голосовых прямо в приложении.
- Поддержка расшифровки голосовых сообщений через серверный `/api/transcribe`.
- Вставка результата расшифровки обратно в поле ввода.

#### 4. Совместимость с веб-версией
- Адаптация payload и логики отправки под реальное поведение `Social-Network-test`.
- Socket-отправка голосовых сообщений для корректного отображения на сайте.
- Совместимость с серверным отображением voice messages не как ссылки, а как голосового блока с плеером.

#### 5. Новости и уведомления
- Вкладка `Новости`, ориентированная на системный/news канал сервера.
- Вкладка `Уведомления` с загрузкой, очисткой, отметкой как прочитанных.
- Корректная обработка серверных форматов ответа и fallback-логика отображения.

#### 6. Раздел друзей
- Список друзей.
- Онлайн-статусы.
- Входящие заявки.
- Поиск пользователей.
- Отправка, принятие и отклонение заявок в друзья.
- Переработанный дизайн вкладки с более аккуратной структурой и glassmorphism-элементами.

#### 7. Звонки
- Аудио- и видеозвонки.
- Встроенный экран звонка в приложении.
- `CallKit`-интеграция для системного входящего вызова на iPhone.
- Поддержка ответа на звонок как из приложения, так и с системного call screen.
- Рингтон входящего вызова внутри приложения и на системном экране.

#### 8. Push и уведомления
- Базовая интеграция APNs.
- Базовая интеграция VoIP PushKit для звонков.
- Локальная обработка входящих событий.
- Отключено системное уведомление о сообщении, если приложение уже открыто на экране, чтобы не дублировать UX внутри активного клиента.

#### 9. Локализация
- Полная локализация интерфейса на русский и английский язык.
- Переведены основные экраны, системные кнопки, экраны звонка, чат, новости, уведомления и настройки.

#### 10. Настройки приложения
- Выбор языка интерфейса.
- Выбор визуальной темы.
- Выбор акцентного цвета.
- Настройка интенсивности стеклянного эффекта.
- Управление предпросмотром ссылок.
- Управление скрытыми preview.
- Выбор рингтона звонка.
- Выбор набора звуков сообщений.
- Предпрослушивание рингтона и звуков сообщений прямо в интерфейсе настроек.

### Крупные UI-доработки
- Улучшен интерфейс страницы чата.
- Переработаны пузырьки сообщений.
- Добавлены минималистичные иконки действий сообщений вместо текстовых кнопок.
- Добавлен emoji picker с отдельной кнопкой и баром выбора эмодзи.
- Улучшен экран звонка в более аккуратном стеклянном стиле.
- Улучшен дизайн вкладки `Друзья`.
- Структурирована и улучшена вкладка `Настройки`.

### Добавленные звуковые сценарии
- Небольшой звук отправки сообщения.
- Отдельный звук входящего сообщения.
- Выбор разных профилей message sounds.
- Выбор разных рингтонов звонка.
- Поддержка `silent`-режима для рингтона и message sounds.

### Особенности реализации
- Для части сценариев использован не только HTTP API, но и socket-совместимая логика, чтобы поведение iOS-клиента совпадало с браузерным клиентом.
- Для аудио и message sounds используются лёгкие локальные `wav`-ресурсы и генерация совместимых тонов.
- Для звонков используется `CallKit`, а для системного входящего интерфейса — конфигурация `CXProvider`.

### Важные технические замечания
- Для полноценных APNs на реальном устройстве нужен полноценный Apple Developer аккаунт и entitlement `aps-environment`.
- `Push Notifications` capability недоступен для `Personal Team`.
- Проверять рингтоны, VoIP и CallKit нужно на реальном iPhone, а не только в симуляторе.
- Совместимость голосовых с веб-версией зависит от того, чтобы сервер и веб-клиент ожидали тот же формат voice/file payload.

### Журнал ключевых доработок
- Нативный клиент мессенджера вместо веб-обёртки.
- Подключение к реальному серверу `voxii.lenuma.ru`.
- Исправление TLS/SSL и серверной адресации.
- Адаптация логики входа и регистрации под веб-проект.
- Реализация и доработка вкладок `Новости` и `Уведомления`.
- Реализация отправки и воспроизведения голосовых.
- Доработка совместимости голосовых с браузерной версией.
- Реализация транскрипции голосовых.
- Реализация звонков и системной обработки входящих вызовов.
- Добавление звуков отправки/получения сообщений.
- Добавление настраиваемых рингтонов и звуков приложения.
- Полная RU/EN локализация интерфейса.

---

## EN

### About the project
**Voxii iOS** is a native iOS messenger client built with `SwiftUI`, connected to a real backend and extended with chat, voice messages, calls, news, notifications, and iPhone system integrations.

This file tracks the main features, architectural decisions, and major improvements made in the project.

### Architecture and core modules
- `SessionStore.swift` — user session, token handling, API-facing session state.
- `VoxiiAPIClient.swift` — HTTP client for auth, DM, friends, notifications, profile, file uploads, and transcription.
- `ChatView.swift` — direct messaging UI, text sending, attachments, voice messages, reactions, edit/reply flow, and calls.
- `MessengerHomeView.swift` — `Messages`, `Friends`, `News`, `Notifications`, and `Settings` tabs.
- `VoxiiSystemCalls.swift` — `CallKit` integration and incoming call/message payload handling.
- `VixiiApp.swift` — notification registration, APNs/VoIP handling, `UNUserNotificationCenter` and `PKPushRegistry` delegates.
- `VoxiiTheme.swift` — theme system, palette, glass layers, and RU/EN localization.
- `VoxiiSocketDMClient.swift` — socket-based DM sending for compatibility with the web-side messaging behavior.

### Implemented functionality

#### 1. Authentication and profile
- Native login and registration UI.
- Authentication flow aligned with the web messenger behavior.
- Current user profile handling.

#### 2. Direct messages
- Text message sending.
- Editing and deleting own messages.
- Replies to messages.
- Reactions.
- Attachments and file support.
- Link previews inside the chat UI.

#### 3. Voice messages
- Voice recording inside the app.
- Voice message sending compatible with the browser messenger.
- In-app playback of voice messages.
- Voice transcription via server `/api/transcribe`.
- Inserting transcription result back into the composer.

#### 4. Web-version compatibility
- Payload and send-flow aligned with the `Social-Network-test` project behavior.
- Socket-based voice message delivery so the web UI can recognize them properly.
- Voice messages are intended to appear as actual voice blocks with playback support instead of plain links.

#### 5. News and notifications
- `News` tab backed by the server-side/system news channel.
- `Notifications` tab with loading, clearing, and mark-as-read flows.
- Additional response-format handling and fallback rendering logic.

#### 6. Friends section
- Friends list.
- Online statuses.
- Pending requests.
- User search.
- Friend request send/accept/reject flows.
- Refined visual design for the friends tab with softer glassmorphism styling.

#### 7. Calls
- Audio and video calls.
- Dedicated in-app call screen.
- `CallKit` integration for system-level incoming calls on iPhone.
- Answering calls both from the app UI and from the system incoming call screen.
- Incoming ringtone both inside the app and on the system call screen.

#### 8. Push and notifications
- APNs integration baseline.
- VoIP PushKit baseline for calls.
- Local handling of incoming events.
- System message notifications are suppressed while the user is already inside the active app, avoiding duplicated UX.

#### 9. Localization
- Full Russian and English UI localization.
- Major screens, chat, calls, news, notifications, and settings are localized.

#### 10. App settings
- Interface language selection.
- Theme selection.
- Accent color selection.
- Glass effect intensity tuning.
- Link preview management.
- Hidden preview reset and management.
- Call ringtone selection.
- Message sound profile selection.
- Built-in ringtone and message sound preview from the settings screen.

### Major UI improvements
- Refined chat screen design.
- Improved message bubbles.
- Replaced text message action buttons with compact minimal icons.
- Added emoji picker with a dedicated button and emoji bar.
- Improved call screen with a cleaner glass-style layout.
- Improved `Friends` tab design.
- Better structured and more visual `Settings` screen.

### Added sound behavior
- Small message send sound.
- Separate incoming message sound.
- Multiple message sound profiles.
- Multiple call ringtone presets.
- `Silent` option for ringtone and message sounds.

### Implementation notes
- Some flows rely not only on pure HTTP API calls but also on socket-compatible behavior so the iOS client matches the browser client.
- Lightweight local `wav` resources and generated tones are used for message sounds and ringtone fallback.
- Calls rely on `CallKit`, while system incoming call presentation is handled through `CXProvider`.

### Important technical notes
- Full APNs on a physical device requires a paid Apple Developer account and the `aps-environment` entitlement.
- `Push Notifications` capability is not available for `Personal Team`.
- Ringtones, VoIP, and `CallKit` should be verified on a real iPhone, not only in Simulator.
- Browser playback for voice messages depends on the server and web client expecting the same voice/file payload structure.

### Key project progress log
- Native messenger client instead of a web wrapper.
- Real backend connection to `voxii.lenuma.ru`.
- TLS/SSL and server addressing fixes.
- Login/registration flow aligned with the web project.
- News and Notifications screen logic implementation.
- Voice message send/playback implementation.
- Web-compatible voice delivery improvements.
- Voice transcription support.
- Calling and system incoming-call handling.
- Message send/receive sound cues.
- Configurable ringtones and in-app sound profiles.
- Full RU/EN localization.
