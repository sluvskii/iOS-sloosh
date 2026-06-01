import Foundation
import UIKit
import WebKit

final class AllohaRuntimeResolver: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
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
    private var hostView: UIView?
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
        guard let url = URL(string: iframeUrl) else {
            throw NSError(domain: "NeomoviesCore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid iframe URL"])
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            Task { @MainActor in
                self.baseURL = url
                self.start(with: url)
            }
        }
    }

    @MainActor
    private func start(with url: URL) {
        let userContentController = WKUserContentController()
        userContentController.add(self, name: "allohaResolver")
        userContentController.addUserScript(
            WKUserScript(
                source: Self.bootstrapScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
        )

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController = userContentController

        let webView = WKWebView(frame: .init(x: -1000, y: -1000, width: 1, height: 1), configuration: configuration)
        webView.navigationDelegate = self
        webView.customUserAgent = Self.nextUserAgent()
        webView.isHidden = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        self.webView = webView

        if let rootView = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.windows.first(where: \.isKeyWindow) })
            .first?
            .rootViewController?
            .view {
            let host = UIView(frame: .zero)
            host.isHidden = true
            host.addSubview(webView)
            rootView.addSubview(host)
            self.hostView = host
        }

        startTimeout()
        webView.loadHTMLString(Self.wrapperHTML(for: url), baseURL: url.deletingLastPathComponent())
    }

    private func startTimeout() {
        let task = DispatchWorkItem { [weak self] in
            guard let self, !self.didFinish else { return }
            self.finish(
                with: NSError(
                    domain: "NeomoviesCore",
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
            scheduleFallbackResolve(for: payload, delay: hasAllohaPlaybackHeaders ? 3.0 : 3.8)
            return
        }

        if isPlayablePayload(payload) {
            bestDirectPayload = payload
            scheduleFallbackResolve(for: payload, delay: 5.0)
        }
    }

    private func resolveBestPayloadIfReady() {
        guard !didFinish else { return }
        if hasAllohaPlaybackHeaders && (bestHlsSourcePayload != nil || bestMasterPayload != nil) {
            resolveBestAvailablePayload(fallback: bestHlsSourcePayload ?? bestMasterPayload ?? "")
        }
    }

    private func resolveBestAvailablePayload(fallback: String) {
        guard let baseURL else { return }
        let payloads = [bestHlsSourcePayload, bestMasterPayload, bestDirectPayload, fallback.isEmpty ? nil : fallback]
            .compactMap { $0 }
        var seen = Set<String>()
        for payload in payloads where seen.insert(payload).inserted {
            let parsed = AllohaRuntimeParser.parsePayload(payload, baseURL: baseURL.absoluteString, headers: headers) ?? [:]
            if let variants = parsed["audioVariants"] as? [[String: Any]],
               let url = variants.first(where: { (($0["url"] as? String) ?? "").isEmpty == false })?["url"] as? String {
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
                    "headers": headers
                ])
                return
            }
            if let url = parsed["videoURL"] as? String, !url.isEmpty {
                finish(with: [
                    "url": url,
                    "subtitles": parsed["subtitles"] ?? [],
                    "audioVariants": [],
                    "qualityVariants": parsed["qualityVariants"] ?? [],
                    "headers": headers
                ])
                return
            }
        }
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
        headers["authorizations"]?.isEmpty == false || headers["accepts-controls"]?.isEmpty == false
    }

    private func isMasterPlaylistPayload(_ payload: String) -> Bool {
        payload.localizedCaseInsensitiveContains("master.m3u8")
    }

    private func isPlayablePayload(_ payload: String) -> Bool {
        payload.localizedCaseInsensitiveContains(".m3u8")
            || payload.localizedCaseInsensitiveContains(".mp4")
            || payload.localizedCaseInsensitiveContains(".mpd")
    }

    private func finish(with result: [String: Any]) {
        guard !didFinish else { return }
        didFinish = true
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
            self.webView?.stopLoading()
            self.webView?.navigationDelegate = nil
            self.webView?.configuration.userContentController.removeScriptMessageHandler(forName: "allohaResolver")
            self.webView?.removeFromSuperview()
            self.hostView?.removeFromSuperview()
            self.webView = nil
            self.hostView = nil
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

    private static let bootstrapScript = """
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
                if (responseUrl.indexOf('/bnsi/') !== -1 && responseText) report(responseText);
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
