import Foundation
import WebKit

@MainActor
final class VoxiiSocketDMClient: NSObject {
    static let shared = VoxiiSocketDMClient()

    private var webView: WKWebView?
    private var loadedServerURL: String?
    private var loadedToken: String?
    private var isReady = false
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var sendContinuation: CheckedContinuation<DirectMessage, Error>?
    private var updateContinuation: CheckedContinuation<DirectMessage, Error>?
    private var pendingSendRequestID: String?
    private var pendingUpdateRequestID: String?

    private override init() {
        super.init()
    }

    func sendMessage(
        serverURL: String,
        token: String,
        currentUser: APIUser,
        receiverID: Int,
        text: String,
        file: APIFileAttachment,
        replyToId: Int?,
        isVoiceMessage: Bool
    ) async throws -> DirectMessage {
        try await ensureReady(serverURL: serverURL, token: token)

        guard sendContinuation == nil, updateContinuation == nil else {
            throw APIClientError.server("Another socket DM operation is already in progress.")
        }

        let requestID = UUID().uuidString
        pendingSendRequestID = requestID
        print("[VoxiiSocketDMClient] Sending socket DM requestId=\(requestID) receiverId=\(receiverID) textLength=\(text.count) fileId=\(file.id)")

        let payload = SocketDMSendCommand(
            requestId: requestID,
            receiverId: receiverID,
            message: SocketDMSendPayload(
                text: text,
                content: text,
                author: currentUser.username,
                avatar: currentUser.avatar,
                timestamp: ISO8601DateFormatter().string(from: Date()),
                file: SendMessageFilePayload(file),
                isVoiceMessage: isVoiceMessage,
                replyTo: replyToId.map(SocketDMSendReply.init)
            )
        )

        let data = try JSONEncoder().encode(payload)
        let json = String(data: data, encoding: .utf8) ?? "{}"

        return try await withCheckedThrowingContinuation { continuation in
            sendContinuation = continuation
            let script = "window.voxiiSendDM(\(json));"
            webView?.evaluateJavaScript(script) { [weak self] _, error in
                guard let self else { return }
                if let error {
                    let wrapped = APIClientError.server("Socket send bootstrap failed: \(error.localizedDescription)")
                    self.finishSend(with: .failure(wrapped))
                }
            }
        }
    }

    func updateMessage(
        serverURL: String,
        token: String,
        receiverID: Int,
        messageID: Int,
        text: String
    ) async throws -> DirectMessage {
        try await ensureReady(serverURL: serverURL, token: token)

        guard sendContinuation == nil, updateContinuation == nil else {
            throw APIClientError.server("Another socket DM operation is already in progress.")
        }

        let requestID = UUID().uuidString
        pendingUpdateRequestID = requestID
        print("[VoxiiSocketDMClient] Updating socket DM requestId=\(requestID) receiverId=\(receiverID) messageId=\(messageID) textLength=\(text.count)")

        let payload = SocketDMUpdateCommand(
            requestId: requestID,
            receiverId: receiverID,
            messageId: messageID,
            newText: text
        )

        let data = try JSONEncoder().encode(payload)
        let json = String(data: data, encoding: .utf8) ?? "{}"

        return try await withCheckedThrowingContinuation { continuation in
            updateContinuation = continuation
            let script = "window.voxiiUpdateDM(\(json));"
            webView?.evaluateJavaScript(script) { [weak self] _, error in
                guard let self else { return }
                if let error {
                    let wrapped = APIClientError.server("Socket update bootstrap failed: \(error.localizedDescription)")
                    self.finishUpdate(with: .failure(wrapped))
                }
            }
        }
    }

    private func ensureReady(serverURL: String, token: String) async throws {
        if loadedServerURL != serverURL || loadedToken != token || webView == nil {
            print("[VoxiiSocketDMClient] Rebuilding socket web view for \(serverURL)")
            rebuildWebView(serverURL: serverURL, token: token)
        }

        if isReady {
            return
        }

        try await withCheckedThrowingContinuation { continuation in
            readyContinuation = continuation
        }
    }

    private func rebuildWebView(serverURL: String, token: String) {
        readyContinuation?.resume(throwing: APIClientError.server("Socket messenger reconfigured."))
        readyContinuation = nil

        finishSend(with: .failure(APIClientError.server("Socket messenger reconfigured.")))
        finishUpdate(with: .failure(APIClientError.server("Socket messenger reconfigured.")))

        isReady = false
        loadedServerURL = serverURL
        loadedToken = token

        let controller = WKUserContentController()
        controller.add(self, name: "voxiiSocketDM")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isHidden = true
        webView.navigationDelegate = self
        webView.loadHTMLString(buildHTML(serverURL: serverURL, token: token), baseURL: URL(string: serverURL))
        self.webView = webView
    }

    private func buildHTML(serverURL: String, token: String) -> String {
        struct Bootstrap: Encodable {
            let serverURL: String
            let token: String
        }

        let normalizedServer = (VoxiiURLBuilder.normalizeBaseURL(serverURL)?.absoluteString ?? serverURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let socketScriptURL = "\(normalizedServer)/socket.io/socket.io.js"
        let bootstrap = Bootstrap(serverURL: normalizedServer, token: token)
        let data = (try? JSONEncoder().encode(bootstrap)) ?? Data("{}".utf8)
        let json = String(data: data, encoding: .utf8) ?? "{}"

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <script src="\(socketScriptURL)"></script>
        </head>
        <body>
          <script>
            const cfg = \(json);
            let socket = null;
            let pendingSend = { requestId: null };
            let pendingUpdate = { requestId: null, messageId: null, receiverId: null };

            function post(type, payload = {}) {
              const handler = window.webkit?.messageHandlers?.voxiiSocketDM;
              if (!handler) return;
              handler.postMessage(Object.assign({ type }, payload));
            }

            function connectSocket() {
              if (typeof io === 'undefined') {
                post('error', { message: 'Socket.IO client is not loaded.' });
                return;
              }

              socket = io(cfg.serverURL, {
                auth: { token: cfg.token },
                transports: ['websocket']
              });

              socket.on('connect', () => {
                post('ready', {});
              });

              socket.on('connect_error', (error) => {
                post('error', { message: error?.message || 'Socket connection failed.' });
              });

              socket.on('dm-sent', (data) => {
                if (!pendingSend.requestId) return;
                post('dm-sent', {
                  requestId: pendingSend.requestId,
                  message: data?.message || null
                });
                pendingSend.requestId = null;
              });

              socket.on('dm-updated', (data) => {
                if (!pendingUpdate.requestId) return;
                const sameMessage = String(data?.message?.id ?? '') === String(pendingUpdate.messageId ?? '');
                const sameReceiver = String(data?.receiverId ?? '') === String(pendingUpdate.receiverId ?? '');
                if (!sameMessage || !sameReceiver) return;
                post('dm-updated', {
                  requestId: pendingUpdate.requestId,
                  message: data?.message || null
                });
                pendingUpdate.requestId = null;
                pendingUpdate.messageId = null;
                pendingUpdate.receiverId = null;
              });

              socket.on('updated-dm', (data) => {
                if (!pendingUpdate.requestId) return;
                const sameMessage = String(data?.message?.id ?? '') === String(pendingUpdate.messageId ?? '');
                const sameReceiver = String(data?.receiverId ?? '') === String(pendingUpdate.receiverId ?? '');
                if (!sameMessage || !sameReceiver) return;
                post('dm-updated', {
                  requestId: pendingUpdate.requestId,
                  message: data?.message || null
                });
                pendingUpdate.requestId = null;
                pendingUpdate.messageId = null;
                pendingUpdate.receiverId = null;
              });
            }

            window.voxiiSendDM = function(payload) {
              if (!socket || !socket.connected) {
                post('send-error', {
                  requestId: payload?.requestId || '',
                  message: 'Socket is not connected.'
                });
                return;
              }

              pendingSend.requestId = payload.requestId;
              socket.emit('send-dm', {
                receiverId: payload.receiverId,
                message: payload.message
              });

              setTimeout(() => {
                if (pendingSend.requestId === payload.requestId) {
                  post('send-error', {
                    requestId: payload.requestId,
                    message: 'Timed out waiting for dm-sent.'
                  });
                  pendingSend.requestId = null;
                }
              }, 12000);
            };

            window.voxiiUpdateDM = function(payload) {
              if (!socket || !socket.connected) {
                post('update-error', {
                  requestId: payload?.requestId || '',
                  message: 'Socket is not connected.'
                });
                return;
              }

              pendingUpdate.requestId = payload.requestId;
              pendingUpdate.messageId = payload.messageId;
              pendingUpdate.receiverId = payload.receiverId;

              socket.emit('update-dm', {
                messageId: payload.messageId,
                newText: payload.newText,
                receiverId: payload.receiverId
              });

              setTimeout(() => {
                if (pendingUpdate.requestId === payload.requestId) {
                  post('update-error', {
                    requestId: payload.requestId,
                    message: 'Timed out waiting for dm-updated.'
                  });
                  pendingUpdate.requestId = null;
                  pendingUpdate.messageId = null;
                  pendingUpdate.receiverId = null;
                }
              }, 12000);
            };

            connectSocket();
          </script>
        </body>
        </html>
        """
    }

    private func finishReady(with result: Result<Void, Error>) {
        guard let readyContinuation else {
            return
        }
        self.readyContinuation = nil
        switch result {
        case .success:
            isReady = true
            readyContinuation.resume()
        case let .failure(error):
            isReady = false
            readyContinuation.resume(throwing: error)
        }
    }

    private func finishSend(with result: Result<DirectMessage, Error>) {
        pendingSendRequestID = nil
        guard let sendContinuation else {
            return
        }
        self.sendContinuation = nil
        switch result {
        case let .success(message):
            sendContinuation.resume(returning: message)
        case let .failure(error):
            sendContinuation.resume(throwing: error)
        }
    }

    private func finishUpdate(with result: Result<DirectMessage, Error>) {
        pendingUpdateRequestID = nil
        guard let updateContinuation else {
            return
        }
        self.updateContinuation = nil
        switch result {
        case let .success(message):
            updateContinuation.resume(returning: message)
        case let .failure(error):
            updateContinuation.resume(throwing: error)
        }
    }
}

extension VoxiiSocketDMClient: WKScriptMessageHandler, WKNavigationDelegate {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "voxiiSocketDM",
              let payload = message.body as? [String: Any],
              let type = payload["type"] as? String else {
            return
        }

        switch type {
        case "ready":
            print("[VoxiiSocketDMClient] Socket ready")
            finishReady(with: .success(()))

        case "error":
            let errorMessage = payload["message"] as? String ?? "Socket messenger error."
            print("[VoxiiSocketDMClient] Socket error: \(errorMessage)")
            let error = APIClientError.server(errorMessage)
            finishReady(with: .failure(error))
            finishSend(with: .failure(error))
            finishUpdate(with: .failure(error))

        case "send-error":
            let requestId = payload["requestId"] as? String
            guard requestId == pendingSendRequestID else {
                return
            }
            let errorMessage = payload["message"] as? String ?? "Socket send failed."
            print("[VoxiiSocketDMClient] Send error requestId=\(requestId ?? "nil"): \(errorMessage)")
            finishSend(with: .failure(APIClientError.server(errorMessage)))

        case "dm-sent":
            let requestId = payload["requestId"] as? String
            guard requestId == pendingSendRequestID else {
                return
            }
            print("[VoxiiSocketDMClient] dm-sent received requestId=\(requestId ?? "nil")")
            guard let rawMessage = payload["message"],
                  JSONSerialization.isValidJSONObject(rawMessage),
                  let data = try? JSONSerialization.data(withJSONObject: rawMessage),
                  let directMessage = try? JSONDecoder().decode(DirectMessage.self, from: data) else {
                finishSend(with: .failure(APIClientError.server("Socket sent an invalid DM payload.")))
                return
            }
            finishSend(with: .success(directMessage))

        case "update-error":
            let requestId = payload["requestId"] as? String
            guard requestId == pendingUpdateRequestID else {
                return
            }
            let errorMessage = payload["message"] as? String ?? "Socket update failed."
            print("[VoxiiSocketDMClient] Update error requestId=\(requestId ?? "nil"): \(errorMessage)")
            finishUpdate(with: .failure(APIClientError.server(errorMessage)))

        case "dm-updated":
            let requestId = payload["requestId"] as? String
            guard requestId == pendingUpdateRequestID else {
                return
            }
            print("[VoxiiSocketDMClient] dm-updated received requestId=\(requestId ?? "nil")")
            guard let rawMessage = payload["message"],
                  JSONSerialization.isValidJSONObject(rawMessage),
                  let data = try? JSONSerialization.data(withJSONObject: rawMessage),
                  let directMessage = try? JSONDecoder().decode(DirectMessage.self, from: data) else {
                finishUpdate(with: .failure(APIClientError.server("Socket sent an invalid DM update payload.")))
                return
            }
            finishUpdate(with: .success(directMessage))

        default:
            break
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let wrapped = APIClientError.server(error.localizedDescription)
        finishReady(with: .failure(wrapped))
        finishSend(with: .failure(wrapped))
        finishUpdate(with: .failure(wrapped))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let wrapped = APIClientError.server(error.localizedDescription)
        finishReady(with: .failure(wrapped))
        finishSend(with: .failure(wrapped))
        finishUpdate(with: .failure(wrapped))
    }
}

private struct SocketDMSendCommand: Encodable {
    let requestId: String
    let receiverId: Int
    let message: SocketDMSendPayload
}

private struct SocketDMUpdateCommand: Encodable {
    let requestId: String
    let receiverId: Int
    let messageId: Int
    let newText: String
}

private struct SocketDMSendPayload: Encodable {
    let text: String
    let content: String
    let author: String
    let avatar: String?
    let timestamp: String
    let file: SendMessageFilePayload
    let isVoiceMessage: Bool
    let replyTo: SocketDMSendReply?
}

private struct SocketDMSendReply: Encodable {
    let id: Int

    init(_ id: Int) {
        self.id = id
    }
}
