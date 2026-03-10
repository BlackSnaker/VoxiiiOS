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
    private var pendingRequestID: String?

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

        guard sendContinuation == nil else {
            throw APIClientError.server("Another socket message is already being sent.")
        }

        let requestID = UUID().uuidString
        pendingRequestID = requestID
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
            let pendingRequestId = null;

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
                if (!pendingRequestId) return;
                post('dm-sent', {
                  requestId: pendingRequestId,
                  message: data?.message || null
                });
                pendingRequestId = null;
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

              pendingRequestId = payload.requestId;
              socket.emit('send-dm', {
                receiverId: payload.receiverId,
                message: payload.message
              });

              setTimeout(() => {
                if (pendingRequestId === payload.requestId) {
                  post('send-error', {
                    requestId: payload.requestId,
                    message: 'Timed out waiting for dm-sent.'
                  });
                  pendingRequestId = null;
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
        pendingRequestID = nil
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

        case "send-error":
            let requestId = payload["requestId"] as? String
            guard requestId == pendingRequestID else {
                return
            }
            let errorMessage = payload["message"] as? String ?? "Socket send failed."
            print("[VoxiiSocketDMClient] Send error requestId=\(requestId ?? "nil"): \(errorMessage)")
            finishSend(with: .failure(APIClientError.server(errorMessage)))

        case "dm-sent":
            let requestId = payload["requestId"] as? String
            guard requestId == pendingRequestID else {
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

        default:
            break
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let wrapped = APIClientError.server(error.localizedDescription)
        finishReady(with: .failure(wrapped))
        finishSend(with: .failure(wrapped))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let wrapped = APIClientError.server(error.localizedDescription)
        finishReady(with: .failure(wrapped))
        finishSend(with: .failure(wrapped))
    }
}

private struct SocketDMSendCommand: Encodable {
    let requestId: String
    let receiverId: Int
    let message: SocketDMSendPayload
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
