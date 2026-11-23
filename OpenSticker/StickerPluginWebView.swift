import SwiftUI
import WebKit

struct StickerPluginWebView: NSViewRepresentable {
    enum Mode: String { case create, card }

    @ObservedObject private var localization = L10n.shared
    let plugin: StickerPlugin
    let mode: Mode
    @Binding var values: [String: String]
    var onFocus: () -> Void = {}
    var onDrag: ((CGSize, CGPoint) -> Void)?
    var onDragEnded: ((CGPoint?) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator, name: "sticker")
        config.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page,
                                                             name: "stickerConfiguration")
        config.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page,
                                                             name: "stickerNetwork")
        config.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page,
                                                             name: "stickerAI")
        let webView = PluginWebView(frame: .zero, configuration: config)
        // The under-page color alone does not disable WebKit's white page backing on macOS.
        webView.underPageBackgroundColor = .clear
        if webView.responds(to: NSSelectorFromString("_setDrawsBackground:")) {
            webView.setValue(false, forKey: "drawsBackground")
        }
        webView.navigationDelegate = context.coordinator
        webView.onFocus = onFocus
        context.coordinator.load(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        let needsReload = coordinator.parent.plugin != plugin || coordinator.parent.mode != mode
        coordinator.parent = self
        (webView as? PluginWebView)?.onFocus = onFocus
        if needsReload || coordinator.loadedLanguage != L10n.language { coordinator.load(in: webView) }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.cancelNetworkRequests()
        coordinator.cancelAIRequest()
        coordinator.finishDrag()
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "sticker")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "stickerConfiguration",
                                                                                contentWorld: .page)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "stickerAI",
                                                                                contentWorld: .page)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "stickerNetwork",
                                                                                contentWorld: .page)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
        var parent: StickerPluginWebView
        private var awaitingInitialNavigation = false
        private var documentID = ""
        private(set) var loadedLanguage = ""
        private var aiTask: Task<Void, Never>?
        private var networkTasks: [UUID: Task<Void, Never>] = [:]
        private var isDragging = false
        private var lastHistorySnapshot: ClipboardHistory.Snapshot?

        init(parent: StickerPluginWebView) { self.parent = parent }

        private var supportsHistory: Bool {
            parent.mode == .card && parent.plugin.id == ClipboardHistory.pluginID
        }

        private func sendHistory(to webView: WKWebView?) {
            let snapshot = ClipboardHistory.shared.snapshot(for: parent.plugin)
            guard let webView, snapshot != lastHistorySnapshot,
                  let bytes = try? JSONEncoder().encode(snapshot) else { return }
            lastHistorySnapshot = snapshot
            webView.callAsyncJavaScript(
                "window.dispatchEvent(new CustomEvent('sticker-history', { detail: JSON.parse(payload) }));",
                arguments: ["payload": String(decoding: bytes, as: UTF8.self)],
                in: nil, in: .page, completionHandler: nil
            )
        }

        func load(in webView: WKWebView) {
            cancelNetworkRequests()
            cancelAIRequest()
            finishDrag()
            webView.stopLoading()
            documentID = UUID().uuidString
            loadedLanguage = L10n.language
            lastHistorySnapshot = nil
            let data = (try? JSONEncoder().encode(parent.values)) ?? Data("{}".utf8)
            let values = String(decoding: data, as: UTF8.self)
            let bootstrap = """
            (() => {
              const values = Object.assign(Object.create(null), \(values));
              const send = window.webkit.messageHandlers.sticker.postMessage.bind(window.webkit.messageHandlers.sticker);
              let userClick = false;
              window.addEventListener("click", event => {
                if (event.isTrusted) {
                  userClick = true;
                  setTimeout(() => { userClick = false; }, 0);
                }
              }, true);
              if ("\(parent.mode.rawValue)" === "card") {
                let origin = null;
                let moving = false;
                window.addEventListener("pointerdown", event => {
                  if (!event.isTrusted || event.button !== 0 ||
                      event.target.closest?.("input, textarea, button, select, label, a, [contenteditable], [role=button], [data-sticker-no-drag]")) return;
                  origin = { id: event.pointerId, x: event.screenX, y: event.screenY };
                  event.target.setPointerCapture(event.pointerId);
                }, true);
                window.addEventListener("pointermove", event => {
                  if (!event.isTrusted || origin?.id !== event.pointerId) return;
                  const dx = event.screenX - origin.x;
                  const dy = event.screenY - origin.y;
                  if (!moving && Math.hypot(dx, dy) < 4) return;
                  moving = true;
                  window.getSelection()?.removeAllRanges();
                  send({document: "\(documentID)", action: "drag", value: String(dx), y: String(dy)});
                }, true);
                const finish = event => {
                  if (!event.isTrusted || origin?.id !== event.pointerId) return;
                  if (moving) send({document: "\(documentID)", action: "dragEnd", value: event.type});
                  origin = null;
                  moving = false;
                };
                window.addEventListener("pointerup", finish, true);
                window.addEventListener("pointercancel", finish, true);
                window.addEventListener("lostpointercapture", finish, true);
              }
              window.OpenSticker = window.Sticker = Object.freeze({
                mode: "\(parent.mode.rawValue)",
                locale: "\(L10n.language.hasPrefix("zh") ? "zh-Hans" : "en")",
                ai: Object.freeze({
                  async generate(prompt, schema) {
                    const result = await window.webkit.messageHandlers.stickerAI.postMessage({
                      document: "\(documentID)", prompt, schema
                    });
                    return JSON.parse(result);
                  }
                }),
                network: Object.freeze({
                  request(options) {
                    return window.webkit.messageHandlers.stickerNetwork.postMessage({
                      document: "\(documentID)", options
                    });
                  }
                }),
                config: Object.freeze({
                  get(key) {
                    return window.webkit.messageHandlers.stickerConfiguration.postMessage({
                      document: "\(documentID)", key
                    });
                  }
                }),
                get(key) { return values[key] ?? ""; },
                set(key, value) {
                  if (typeof key !== "string" || typeof value !== "string"
                      || key.length < 1 || key.length > 128 || value.length > 32768) return;
                  values[key] = value;
                  send({document: "\(documentID)", action: "set", key, value});
                },
                ...("\(supportsHistory)" === "true" ? {
                  history: Object.freeze({
                    refresh() { send({document: "\(documentID)", action: "history", value: "refresh"}); },
                    perform(action, item = "") {
                      if (userClick && ["start", "pause", "clear", "copy"].includes(action)) {
                        send({document: "\(documentID)", action: "history", value: action, item});
                      }
                    }
                  })
                } : {}),
                copy(value) {
                  if (userClick && typeof value === "string" && value.length <= 32768) {
                    send({document: "\(documentID)", action: "copy", value});
                  }
                }
              });
            })();
            """
            let controller = webView.configuration.userContentController
            controller.removeAllUserScripts()
            controller.addUserScript(WKUserScript(source: bootstrap, injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: true))
            controller.addUserScript(WKUserScript(source: parent.plugin.script, injectionTime: .atDocumentEnd,
                                                  forMainFrameOnly: true))
            awaitingInitialNavigation = true
            webView.loadHTMLString("""
            <!doctype html><meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'">
            <style>html, body { background-color: transparent; }</style>
            \(parent.plugin.html)
            """, baseURL: nil)
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame,
                  let body = message.body as? [String: String], body["document"] == documentID,
                  let value = body["value"], value.utf8.count <= 98_304 else { return }
            switch body["action"] {
            case "set":
                guard !supportsHistory, let key = body["key"], (1...128).contains(key.utf8.count) else { return }
                var updated = parent.values
                updated[key] = value
                guard updated.count <= 128, updated != parent.values else { return }
                parent.values = updated
            case "copy":
                copyToClipboard(value)
            case "history":
                guard supportsHistory,
                      StickerPluginRegistry.shared.plugins.contains(parent.plugin) else { return }
                handleHistory(value, item: body["item"], webView: message.webView)
            case "drag":
                guard parent.mode == .card, let x = Double(value), let y = body["y"].flatMap(Double.init),
                      x.isFinite, y.isFinite else { return }
                isDragging = true
                guard let point = pointerPosition(in: message.webView) else { return }
                parent.onDrag?(CGSize(width: x, height: y), point)
            case "dragEnd":
                finishDrag(at: value == "pointerup" ? pointerPosition(in: message.webView) : nil)
            default:
                break
            }
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage,
                                   replyHandler: @escaping (Any?, String?) -> Void) {
            if message.name == "stickerAI" {
                handleAI(message, reply: replyHandler)
                return
            }
            if message.name == "stickerNetwork" {
                handleNetwork(message, reply: replyHandler)
                return
            }
            let plugin = parent.plugin
            guard message.frameInfo.isMainFrame,
                  let body = message.body as? [String: String], body["document"] == documentID,
                  let key = body["key"], plugin.manifest.configuration?.contains(where: { $0.key == key }) == true,
                  StickerPluginRegistry.shared.plugins.contains(plugin),
                  PluginConfiguration.shared.isAuthorized(plugin) else {
                replyHandler(nil, L10n.text("插件未获准读取这项配置。"))
                return
            }
            do {
                if let value = try PluginConfiguration.shared.value(for: key) {
                    replyHandler(value, nil)
                } else {
                    replyHandler(NSNull(), nil)
                }
            } catch {
                replyHandler(nil, L10n.text("无法读取共享配置。"))
            }
        }

        func cancelAIRequest() {
            aiTask?.cancel()
        }

        private func handleAI(_ message: WKScriptMessage, reply: @escaping (Any?, String?) -> Void) {
            let plugin = parent.plugin
            guard message.frameInfo.isMainFrame, parent.mode == .card,
                  let body = message.body as? [String: Any], body["document"] as? String == documentID,
                  plugin.manifest.usesLocalAI == true,
                  StickerPluginRegistry.shared.plugins.contains(plugin),
                  PluginConfiguration.shared.isAIAuthorized(plugin) else {
                reply(nil, L10n.text("请在插件配置中授权使用 AI 能力。"))
                return
            }
            guard let prompt = body["prompt"] as? String, (1...4096).contains(prompt.utf8.count),
                  let schema = body["schema"] as? [String: Any], schema["type"] as? String == "object",
                  JSONSerialization.isValidJSONObject(schema),
                  let data = try? JSONSerialization.data(withJSONObject: schema), data.count <= 8192 else {
                reply(nil, L10n.text("AI 请求参数无效。"))
                return
            }
            guard aiTask == nil else {
                reply(nil, L10n.text("AI 正在处理另一条请求。"))
                return
            }
            let document = documentID
            aiTask = Task { @MainActor [weak self] in
                defer { self?.aiTask = nil }
                do {
                    let result = try await PluginAI.run(prompt: prompt, schema: data)
                    guard self?.documentID == document,
                          StickerPluginRegistry.shared.plugins.contains(plugin),
                          PluginConfiguration.shared.isAIAuthorized(plugin) else { throw CancellationError() }
                    reply(String(decoding: result, as: UTF8.self), nil)
                } catch PluginAI.Failure.unavailable {
                    reply(nil, L10n.text("请先在插件配置中填写模型服务信息。"))
                } catch PluginAI.Failure.busy {
                    reply(nil, L10n.text("AI 正在处理另一条请求。"))
                } catch PluginAI.Failure.timedOut {
                    reply(nil, L10n.text("AI 请求超时。"))
                } catch PluginAI.Failure.http(let status) {
                    reply(nil, L10n.format("模型服务返回 HTTP %@。", String(status)))
                } catch is CancellationError {
                    reply(nil, L10n.text("AI 请求已取消。"))
                } catch {
                    reply(nil, L10n.text("模型请求失败，请检查服务地址或响应格式。"))
                }
            }
        }

        func cancelNetworkRequests() {
            for task in networkTasks.values { task.cancel() }
            networkTasks.removeAll()
        }

        private func handleNetwork(_ message: WKScriptMessage, reply: @escaping (Any?, String?) -> Void) {
            let plugin = parent.plugin
            guard message.frameInfo.isMainFrame,
                  let body = message.body as? [String: Any], body["document"] as? String == documentID,
                  let input = body["options"] as? [String: Any],
                  StickerPluginRegistry.shared.plugins.contains(plugin),
                  PluginConfiguration.shared.isNetworkAuthorized(plugin),
                  let request = PluginNetwork.request(from: input, hosts: plugin.manifest.networkHosts ?? []) else {
                reply(nil, L10n.text("插件网络请求未获授权或参数无效。"))
                return
            }
            guard networkTasks.count < 4 else {
                reply(nil, L10n.text("插件网络请求过多。"))
                return
            }
            let id = UUID()
            let document = documentID
            networkTasks[id] = Task { @MainActor [weak self] in
                defer { self?.networkTasks.removeValue(forKey: id) }
                do {
                    let response = try await PluginNetwork.send(request)
                    guard !Task.isCancelled, self?.documentID == document,
                          StickerPluginRegistry.shared.plugins.contains(plugin),
                          PluginConfiguration.shared.isNetworkAuthorized(plugin) else {
                        reply(nil, L10n.text("插件网络请求已取消。"))
                        return
                    }
                    reply(response, nil)
                } catch {
                    reply(nil, L10n.text("插件网络请求失败。"))
                }
            }
        }

        private func handleHistory(_ action: String, item: String?, webView: WKWebView?) {
            let history = ClipboardHistory.shared
            switch action {
            case "start": history.start(for: parent.plugin)
            case "pause": history.pause(for: parent.plugin)
            case "clear": history.clear(for: parent.plugin)
            case "copy":
                if let item, let id = UUID(uuidString: item) { history.copy(id, for: parent.plugin) }
            case "refresh": break
            default: return
            }
            sendHistory(to: webView)
        }

        private func pointerPosition(in webView: WKWebView?) -> CGPoint? {
            guard let frame = webView?.window?.frame else { return nil }
            let mouse = NSEvent.mouseLocation
            return CGPoint(x: mouse.x - frame.minX, y: frame.maxY - mouse.y)
        }

        func finishDrag(at position: CGPoint? = nil) {
            guard isDragging else { return }
            isDragging = false
            parent.onDragEnded?(position)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if awaitingInitialNavigation, action.targetFrame?.isMainFrame == true,
               action.request.url?.absoluteString == "about:blank" {
                awaitingInitialNavigation = false
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }

    private final class PluginWebView: WKWebView {
        var onFocus: (() -> Void)?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            onFocus?()
            window?.makeFirstResponder(self)
            super.mouseDown(with: event)
        }
    }
}
