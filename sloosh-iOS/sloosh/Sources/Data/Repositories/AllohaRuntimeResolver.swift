import Foundation
import UIKit
import WebKit

final class AllohaRuntimeResolver: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private static var iframeCache: [String: (result: [String: Any], expiresAt: Date)] = [:]
    private static let cacheTtl: TimeInterval = 20 // 20 секунд — достаточно для повторных переходов, не мешает смене озвучки
    private static let cacheQueue = DispatchQueue(label: "ru.neomovies.alloharesolver.cache", attributes: .concurrent)

    /// Инвалидирует кэш для конкретного iframeUrl (используется при смене озвучки)
    static func invalidateCache(for iframeUrl: String) {
        cacheQueue.async(flags: .barrier) {
            iframeCache.removeValue(forKey: iframeUrl)
        }
    }

    private static var uaIndex = 0
    private static let userAgents = [
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36",
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36"
    ]

    @MainActor
    private static func nextUserAgent() -> String {
        let idx = uaIndex % userAgents.count
        uaIndex += 1
        return userAgents[idx]
    }

    private var webView: WKWebView?
    private var timeoutTask: DispatchWorkItem?
    private var fallbackTask: DispatchWorkItem?
    private var didFinish = false
    private var headers: [String: String] = [:]
    private var pendingPayloads: [String] = []
    private var bestMasterPayload: String?
    private var bestHlsSourcePayload: String?
    private var bestDirectPayload: String?
    private var continuation: CheckedContinuation<[String: Any], Error>?
    private var baseURL: URL?

    func resolve(iframeUrl: String) async throws -> [String: Any] {
        let cached = Self.cacheQueue.sync { Self.iframeCache[iframeUrl] }
        if let cached = cached, cached.expiresAt > Date() {
            return cached.result
        }

        guard let url = URL(string: iframeUrl) else {
            throw NSError(domain: "SlooshCore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid iframe URL"])
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                Task { @MainActor in
                    self.baseURL = url
                    self.start(with: url)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel()
            }
        }
    }

    @MainActor
    func cancel() {
        finish(with: CancellationError())
    }

    @MainActor
    private func start(with url: URL) {
        let provider = SharedWebViewProvider.shared
        provider.prepare(for: self)
        
        self.webView = provider.webView
        self.webView?.customUserAgent = Self.nextUserAgent()

        startTimeout()
        self.webView?.loadHTMLString(Self.wrapperHTML(for: url), baseURL: url.deletingLastPathComponent())
    }

    private func startTimeout() {
        let task = DispatchWorkItem { [weak self] in
            guard let self, !self.didFinish else { return }
            self.finish(
                with: NSError(
                    domain: "SlooshCore",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Alloha runtime parser did not return playable URL (timeout)"]
                )
            )
        }
        timeoutTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: task)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !didFinish,
              let body = message.body as? [String: Any] else {
            return
        }

        if let incoming = Self.stringDictionary(from: body["headers"]) {
            headers.merge(incoming) { _, new in new }
            resolveBestPayloadIfReady()
        }

        guard let payload = body["payload"] as? String, !payload.isEmpty else {
            return
        }

        pendingPayloads.append(payload)
        if pendingPayloads.count > 12 {
            pendingPayloads.removeFirst(pendingPayloads.count - 12)
        }

        if isMasterPlaylistPayload(payload) {
            bestMasterPayload = payload
            scheduleFallbackResolve(for: payload, delay: bestHlsSourcePayload == nil ? 2.4 : 0.8)
            return
        }

        resolveIfReady(payload)
    }

    private func resolveIfReady(_ payload: String) {
        guard !didFinish else { return }

        if payload.contains("hlsSource") {
            bestHlsSourcePayload = payload
            // Если заголовки уже есть — парсим быстро, иначе даём время WS config_update
            let delay: TimeInterval = hasAllohaPlaybackHeaders ? 0.5 : 4.5
            scheduleFallbackResolve(for: payload, delay: delay)
            // Если заголовки уже есть — попробуем сразу
            if hasAllohaPlaybackHeaders {
                resolveBestAvailablePayload(fallback: payload)
            }
            return
        }

        if isPlayablePayload(payload) {
            bestDirectPayload = payload
            scheduleFallbackResolve(for: payload, delay: hasAllohaPlaybackHeaders ? 1.5 : 5.0)
        }
    }

    private func resolveBestPayloadIfReady() {
        guard !didFinish else { return }
        if hasAllohaPlaybackHeaders && (bestHlsSourcePayload != nil || bestMasterPayload != nil) {
            resolveBestAvailablePayload(fallback: bestHlsSourcePayload ?? bestMasterPayload ?? "")
        } else if hasAllohaPlaybackHeaders && bestDirectPayload != nil {
            // Нет hlsSource, но есть прямая ссылка + заголовки
            resolveBestAvailablePayload(fallback: bestDirectPayload ?? "")
        }
    }

    private func resolveBestAvailablePayload(fallback: String) {
        guard let baseURL else { return }
        let payloads = [bestHlsSourcePayload, bestMasterPayload, bestDirectPayload, fallback.isEmpty ? nil : fallback]
            .compactMap { $0 }
        var seen = Set<String>()
        for payload in payloads where seen.insert(payload).inserted {
            let parsed = AllohaRuntimeParser.parsePayload(payload, baseURL: baseURL.absoluteString, headers: headers) ?? [:]
            if let variants = parsed["audioVariants"] as? [[String: Any]] {
                var chosenUrl: String? = nil
                if let master = bestMasterPayload, !master.isEmpty {
                    chosenUrl = master
                } else {
                    chosenUrl = variants.first(where: { (($0["url"] as? String) ?? "").isEmpty == false })?["url"] as? String
                }
                
                if let url = chosenUrl {
                    let mappedVariants = variants.compactMap { item -> [String: Any]? in
                        guard let variantUrl = item["url"] as? String, !variantUrl.isEmpty else { return nil }
                        let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let qualityVariants = (item["qualityVariants"] as? [[String: Any]]) ?? []
                        return [
                            "title": (title?.isEmpty == false) ? title! : "Unknown",
                            "url": variantUrl,
                            "qualityVariants": qualityVariants
                        ]
                    }
                    finish(with: [
                        "url": url,
                        "subtitles": parsed["subtitles"] ?? [],
                        "audioVariants": mappedVariants,
                        "qualityVariants": parsed["qualityVariants"] ?? [],
                        "headers": headers,
                        "introRange": (parsed["introRange"] ?? NSNull()) as Any,
                        "outroRange": (parsed["outroRange"] ?? NSNull()) as Any
                    ])
                    return
                }
            }
            if let url = parsed["videoURL"] as? String, !url.isEmpty {
                finish(with: [
                    "url": url,
                    "subtitles": parsed["subtitles"] ?? [],
                    "audioVariants": [],
                    "qualityVariants": parsed["qualityVariants"] ?? [],
                    "headers": headers,
                    "introRange": (parsed["introRange"] ?? NSNull()) as Any,
                    "outroRange": (parsed["outroRange"] ?? NSNull()) as Any
                ])
                return
            }
        }
        // Если ни один payload не дал результат, но у нас есть мастер-плейлист URL — вернём его напрямую
        if let masterUrl = bestMasterPayload, !masterUrl.isEmpty,
           masterUrl.contains("http"), masterUrl.contains(".m3u8") {
            finish(with: [
                "url": masterUrl,
                "subtitles": [],
                "audioVariants": [],
                "qualityVariants": [],
                "headers": headers
            ])
            return
        }
        // Если есть любая прямая воспроизводимая ссылка — вернём её
        if let directUrl = bestDirectPayload, !directUrl.isEmpty,
           directUrl.contains("http"), isPlayableURL(directUrl) {
            finish(with: [
                "url": directUrl,
                "subtitles": [],
                "audioVariants": [],
                "qualityVariants": [],
                "headers": headers
            ])
        }
        // Иначе ждём следующего payload или таймаута
    }

    private func scheduleFallbackResolve(for payload: String, delay: TimeInterval) {
        fallbackTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self, !self.didFinish else { return }
            self.resolveBestAvailablePayload(fallback: payload)
        }
        fallbackTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    private var hasAllohaPlaybackHeaders: Bool {
        headers["authorizations"]?.isEmpty == false
            || headers["accepts-controls"]?.isEmpty == false
            || headers["authorization"]?.isEmpty == false
    }

    private func isLikelyURL(_ payload: String) -> Bool {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("<") || trimmed.contains(" ") { return false }
        return trimmed.hasPrefix("http") || trimmed.hasPrefix("//")
    }

    private func isMasterPlaylistPayload(_ payload: String) -> Bool {
        guard isLikelyURL(payload) else { return false }
        return payload.localizedCaseInsensitiveContains("master.m3u8")
    }

    private func isPlayableURL(_ url: String) -> Bool {
        let lower = url.lowercased()
        if lower.contains("blank.mp4") || lower.contains("cdn.plyr.io") { return false }
        return lower.contains(".m3u8") || lower.contains(".mp4") || lower.contains(".mpd")
    }

    private func isPlayablePayload(_ payload: String) -> Bool {
        guard isLikelyURL(payload) else { return false }
        let lower = payload.lowercased()
        if lower.contains("blank.mp4") || lower.contains("cdn.plyr.io") { return false }
        return lower.contains(".m3u8")
            || lower.contains(".mp4")
            || lower.contains(".mpd")
    }

    private func finish(with result: [String: Any]) {
        guard !didFinish else { return }
        didFinish = true

        if let originalUrl = baseURL?.absoluteString {
            Self.cacheQueue.async(flags: .barrier) {
                Self.iframeCache[originalUrl] = (result: result, expiresAt: Date().addingTimeInterval(Self.cacheTtl))
            }
        }

        cleanup()
        continuation?.resume(returning: result)
        continuation = nil
    }

    private func finish(with error: Error) {
        guard !didFinish else { return }
        didFinish = true
        cleanup()
        continuation?.resume(throwing: error)
        continuation = nil
    }

    private func cleanup() {
        timeoutTask?.cancel()
        fallbackTask?.cancel()
        timeoutTask = nil
        fallbackTask = nil
        Task { @MainActor in
            SharedWebViewProvider.shared.reset()
            self.webView = nil
        }
    }

    private static func stringDictionary(from value: Any?) -> [String: String]? {
        guard let dictionary = value as? [String: Any] else {
            return value as? [String: String]
        }
        return dictionary.reduce(into: [String: String]()) { result, pair in
            result[pair.key.lowercased()] = String(describing: pair.value)
        }
    }

    private static func wrapperHTML(for url: URL) -> String {
        """
        <!doctype html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
            <style>html, body, iframe { margin:0; width:100%; height:100%; background:#000; overflow:hidden; }</style>
        </head>
        <body>
            <iframe id="alloha_iframe" src="\(url.absoluteString)" allow="autoplay; fullscreen; encrypted-media; picture-in-picture" allowfullscreen frameborder="0"></iframe>
        </body>
        </html>
        """
    }

    fileprivate static let bootstrapScript = """
    (function() {
      if (window.__neoAllohaResolverInstalled) return;
      window.__neoAllohaResolverInstalled = true;

      var capturedHeaders = {};
      var lastPayload = '';
      var lastM3u8 = '';

      function post(type, payload) {
        try {
          window.webkit.messageHandlers.allohaResolver.postMessage({ type: type, payload: payload || '', headers: capturedHeaders });
        } catch(e) {}
      }

      function putHeader(name, value) {
        if (!name || !value) return;
        capturedHeaders[String(name).toLowerCase()] = String(value);
      }

      function defaultHeaders(win) {
        try {
          putHeader('origin', win.location.origin);
          putHeader('referer', win.location.origin + '/');
          putHeader('user-agent', win.navigator.userAgent);
          putHeader('accept', '*/*');
          putHeader('sec-fetch-dest', 'empty');
          putHeader('sec-fetch-mode', 'cors');
          putHeader('sec-fetch-site', 'cross-site');
        } catch(e) {}
      }

      function looksPlayable(text) {
        return typeof text === 'string' && (
          text.indexOf('hlsSource') !== -1 ||
          text.indexOf('.m3u8') !== -1 ||
          text.indexOf('.mp4') !== -1 ||
          text.indexOf('.vtt') !== -1
        );
      }

      function report(payload) {
        if (!looksPlayable(payload)) return;
        if (payload === lastPayload) return;
        lastPayload = payload;
        post('payload', payload);
      }

      function scan(win) {
        try {
          defaultHeaders(win);
          var chunks = [];
          if (win.location && win.location.href) chunks.push(win.location.href);
          if (win.document && win.document.documentElement) chunks.push(win.document.documentElement.outerHTML);
          var media = win.document ? win.document.querySelectorAll('video, source, track') : [];
          for (var i = 0; i < media.length; i++) chunks.push(media[i].currentSrc || media[i].src || media[i].getAttribute('src') || '');
          if (win.performance && win.performance.getEntriesByType) {
            var entries = win.performance.getEntriesByType('resource');
            for (var p = 0; p < entries.length; p++) chunks.push(entries[p].name || '');
          }
          report(chunks.join('\\n'));
        } catch(e) {}
      }

      function install(win) {
        try {
          if (!win || win.__neoAllohaHooksInstalled) return;
          win.__neoAllohaHooksInstalled = true;
          defaultHeaders(win);

          var originalOpen = win.XMLHttpRequest && win.XMLHttpRequest.prototype.open;
          var originalSetHeader = win.XMLHttpRequest && win.XMLHttpRequest.prototype.setRequestHeader;
          if (originalOpen && originalSetHeader) {
            win.XMLHttpRequest.prototype.open = function(method, requestUrl) {
              this.__neoAllohaUrl = requestUrl || '';
              this.addEventListener('load', function() {
                var responseUrl = this.responseURL || this.__neoAllohaUrl || '';
                var responseText = '';
                try { responseText = this.responseText || ''; } catch(e) {}
                // Перехватываем /bnsi/ и любой JSON, содержащий hlsSource
                if (responseUrl.indexOf('/bnsi/') !== -1 && responseText) report(responseText);
                if (responseText && responseText.indexOf('hlsSource') !== -1) report(responseText);
                if (looksPlayable(responseText)) report(responseText);
                if (responseUrl.indexOf('master.m3u8') !== -1 && responseUrl !== lastM3u8) { lastM3u8 = responseUrl; post('payload', responseUrl); }
              });
              return originalOpen.apply(this, arguments);
            };
            win.XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
              putHeader(name, value);
              return originalSetHeader.apply(this, arguments);
            };
          }

          var originalFetch = win.fetch;
          if (originalFetch) {
            win.fetch = function(input, init) {
              try {
                var requestUrl = (typeof input === 'string') ? input : (input && input.url ? input.url : '');
                if (init && init.headers) {
                  if (typeof init.headers.forEach === 'function') init.headers.forEach(function(value, name) { putHeader(name, value); });
                  else for (var key in init.headers) putHeader(key, init.headers[key]);
                }
                if (input && input.headers && typeof input.headers.forEach === 'function') input.headers.forEach(function(value, name) { putHeader(name, value); });
                if (looksPlayable(requestUrl)) post('payload', requestUrl);
              } catch(e) {}

              return originalFetch.apply(this, arguments).then(function(response) {
                try {
                  var responseUrl = response.url || '';
                  if (looksPlayable(responseUrl)) post('payload', responseUrl);
                  var clone = response.clone();
                  clone.text().then(function(text) { report(text); }).catch(function(){});
                } catch(e) {}
                return response;
              });
            };
          }

          var originalSend = win.WebSocket && win.WebSocket.prototype.send;
          if (originalSend) {
            win.WebSocket.prototype.send = function(data) {
              if (!this.__neoAllohaWsHooked) {
                this.__neoAllohaWsHooked = true;
                this.addEventListener('message', function(event) {
                  try {
                    var msg = JSON.parse(event.data);
                    if (msg && msg.type === 'config_update' && msg.edge_hash) {
                      putHeader('accepts-controls', msg.edge_hash);
                      if (msg.ttl) putHeader('x-neo-config-ttl', String(msg.ttl));
                      post('headers', '');
                    }
                  } catch(e) {}
                });
              }
              return originalSend.apply(this, arguments);
            };
          }
        } catch(e) {}
      }

      function tick() {
        install(window);
        scan(window);
        try {
          var frames = document.querySelectorAll('iframe');
          for (var i = 0; i < frames.length; i++) { install(frames[i].contentWindow); scan(frames[i].contentWindow); }
        } catch(e) {}
      }

      tick();
      setInterval(tick, 700);
      window.addEventListener('load', tick);
    })();
    """
}

@MainActor
final class SharedWebViewProvider {
    static let shared = SharedWebViewProvider()
    var webView: WKWebView?
    private var hostView: UIView?
    
    private init() {
        // No background killing; keep webview alive so background playback and proxy work
    }
    
    private func destroyWebView() {
        reset()
        webView?.removeFromSuperview()
        hostView?.removeFromSuperview()
        webView = nil
        hostView = nil
    }
    
    func prepare(for delegate: WKNavigationDelegate & WKScriptMessageHandler) {
        if webView == nil {
            let config = WKWebViewConfiguration()
            let uc = WKUserContentController()
            config.userContentController = uc
            
            config.allowsInlineMediaPlayback = true
            config.mediaTypesRequiringUserActionForPlayback = []
            
            let prefs = WKWebpagePreferences()
            prefs.allowsContentJavaScript = true
            config.defaultWebpagePreferences = prefs
            
            let newWebView = WKWebView(frame: .init(x: -1000, y: -1000, width: 1, height: 1), configuration: config)
            newWebView.isHidden = true
            newWebView.isOpaque = false
            newWebView.backgroundColor = .clear
            self.webView = newWebView
            
            if let rootView = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.windows.first(where: \.isKeyWindow) })
                .first?
                .rootViewController?
                .view {
                let host = UIView(frame: .zero)
                host.isHidden = true
                host.addSubview(newWebView)
                rootView.addSubview(host)
                self.hostView = host
            }
        }
        
        if let uc = webView?.configuration.userContentController {
            uc.removeAllUserScripts()
            uc.removeScriptMessageHandler(forName: "allohaResolver")
            
            uc.addUserScript(
                WKUserScript(
                    source: AllohaRuntimeResolver.bootstrapScript,
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: false
                )
            )
            uc.add(delegate, name: "allohaResolver")
        }
        webView?.navigationDelegate = delegate
    }
    
    func reset() {
        if let uc = webView?.configuration.userContentController {
            uc.removeScriptMessageHandler(forName: "allohaResolver")
        }
        webView?.navigationDelegate = nil
        webView?.loadHTMLString("", baseURL: nil)
    }
}
