import Foundation
import WebKit
import UIKit

@MainActor
protocol AllohaParserDelegate: AnyObject {
    func onHlsLinksReceived(json: String, extraHeaders: [String: String])
    func onConfigUpdate(edgeHash: String, ttlSeconds: Int, extraHeaders: [String: String])
    func onM3u8Refreshed(url: String, extraHeaders: [String: String])
    func onStreamHeadersUpdated(extraHeaders: [String: String])
    func onError(error: String)
}

@MainActor
class AllohaParser: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    
    weak var delegate: AllohaParserDelegate?
    private var webView: WKWebView!
    private weak var hostView: UIView?
    private var timeoutWorkItem: DispatchWorkItem?
    
    private let userAgents = (0...19).map { _ in
        let osOptions = [
            "Windows NT 10.0; Win64; x64",
            "Windows NT 11.0; Win64; x64",
            "Macintosh; Intel Mac OS X 10_15_7",
            "Macintosh; Intel Mac OS X 14_4_1",
            "X11; Linux x86_64",
            "X11; Ubuntu; Linux x86_64"
        ]
        let os = osOptions.randomElement() ?? osOptions[0]
        let chromeVersion = Int.random(in: 130...135)
        let firefoxVersion = Int.random(in: 130...136)

        switch Int.random(in: 0...2) {
        case 0:
            return "Mozilla/5.0 (\(os)) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(chromeVersion).0.0.0 Safari/537.36"
        case 1:
            return "Mozilla/5.0 (\(os); rv:\(firefoxVersion).0) Gecko/20100101 Firefox/\(firefoxVersion).0"
        default:
            return "Mozilla/5.0 (\(os)) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/\(chromeVersion).0.0.0 Safari/537.36 Edg/\(chromeVersion).0.0.0"
        }
    }
    private var userAgentIndex = Int.random(in: 0...19)
    private var userAgent: String { userAgents[userAgentIndex] }
    
    override init() {
        super.init()
        setupWebView()
    }
    
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.websiteDataStore = .default()
        
        let userContentController = WKUserContentController()
        userContentController.add(self, name: "AndroidBridge")
        config.userContentController = userContentController
        
        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = userAgent
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.isHidden = false
    }
    
    func parse(iframeUrl: String) {
        rotateUserAgent()
        attachIfNeeded()
        timeoutWorkItem?.cancel()
        webView.stopLoading()

        let wrapperHtml = buildWrapperHtml(iframeUrl: iframeUrl)
        if let url = URL(string: iframeUrl), let host = url.host {
            let baseUrl = URL(string: "\(url.scheme ?? "https")://\(host)/")
            webView.loadHTMLString(wrapperHtml, baseURL: baseUrl)
            let timeoutWorkItem = DispatchWorkItem { [weak self] in
                self?.delegate?.onError(error: "Таймаут парсинга iframe")
            }
            self.timeoutWorkItem = timeoutWorkItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: timeoutWorkItem)
        } else {
            delegate?.onError(error: "Некорректный iframe URL")
        }
    }
    
    func release() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "AndroidBridge")
        webView.stopLoading()
        webView.removeFromSuperview()
        hostView = nil
        webView = nil
    }

    private func rotateUserAgent() {
        userAgentIndex = (userAgentIndex + 1) % userAgents.count
        webView.customUserAgent = userAgent
    }

    private func attachIfNeeded() {
        guard webView.superview == nil else { return }
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = windowScene.windows.first(where: \.isKeyWindow) ?? windowScene.windows.first,
              let rootView = window.rootViewController?.view else {
            return
        }

        let host = UIView(frame: CGRect(x: -2, y: -2, width: 1, height: 1))
        host.isUserInteractionEnabled = false
        host.alpha = 0.01
        host.clipsToBounds = true
        webView.frame = host.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(webView)
        rootView.addSubview(host)
        hostView = host
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any], let method = dict["method"] as? String else { return }
        
        switch method {
        case "onReady":
            timeoutWorkItem?.cancel()
            if let jsonResponse = dict["jsonResponse"] as? String,
               let headersJson = dict["headersJson"] as? String {
                UIPasteboard.general.string = jsonResponse
                delegate?.onHlsLinksReceived(json: jsonResponse, extraHeaders: parseHeaders(headersJson))
            }
        case "onConfigUpdate":
            if let edgeHash = dict["edgeHash"] as? String,
               let ttl = dict["ttl"] as? Int,
               let headersJson = dict["headersJson"] as? String {
                delegate?.onConfigUpdate(edgeHash: edgeHash, ttlSeconds: ttl, extraHeaders: parseHeaders(headersJson))
            }
        case "onM3u8Refreshed":
            if let url = dict["url"] as? String,
               let headersJson = dict["headersJson"] as? String {
                delegate?.onM3u8Refreshed(url: url, extraHeaders: parseHeaders(headersJson))
            }
        case "onStreamHeaders":
            if let headersJson = dict["headersJson"] as? String {
                delegate?.onStreamHeadersUpdated(extraHeaders: parseHeaders(headersJson))
            }
        case "onLog":
            if let msg = dict["msg"] as? String {
                print("AllohaParserJS: \(msg)")
            }
        default:
            break
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("AllohaParser: wrapper loaded")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        timeoutWorkItem?.cancel()
        delegate?.onError(error: error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        timeoutWorkItem?.cancel()
        delegate?.onError(error: error.localizedDescription)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        timeoutWorkItem?.cancel()
        delegate?.onError(error: "Web content process terminated")
    }
    
    private func parseHeaders(_ headersJson: String) -> [String: String] {
        guard let data = headersJson.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return dict
    }
    
    private func buildWrapperHtml(iframeUrl: String) -> String {
        return """
        <html>
        <body style="margin:0;padding:0;background:black;">
            <iframe id="alloha_iframe" src="\(iframeUrl)" width="100%" height="100%" frameborder="0" allowfullscreen></iframe>
            <script>
                function sendToSwift(method, args) {
                    try {
                        args['method'] = method;
                        window.webkit.messageHandlers.AndroidBridge.postMessage(args);
                    } catch(e) {}
                }

                var AndroidBridge = {
                    onReady: function(jsonResponse, headersJson) { sendToSwift('onReady', {jsonResponse: jsonResponse, headersJson: headersJson}); },
                    onConfigUpdate: function(edgeHash, ttl, headersJson) { sendToSwift('onConfigUpdate', {edgeHash: edgeHash, ttl: ttl, headersJson: headersJson}); },
                    onM3u8Refreshed: function(url, headersJson) { sendToSwift('onM3u8Refreshed', {url: url, headersJson: headersJson}); },
                    onStreamHeaders: function(headersJson) { sendToSwift('onStreamHeaders', {headersJson: headersJson}); },
                    onLog: function(msg) { sendToSwift('onLog', {msg: msg}); }
                };

                try {
                    Object.defineProperty(document, 'visibilityState', { get: () => 'visible' });
                    Object.defineProperty(document, 'hidden', { get: () => false });
                } catch(e) {}

                var iframe = document.getElementById('alloha_iframe');
                iframe.onload = function() {
                    try {
                        var iframeWin = iframe.contentWindow;

                        try {
                            Object.defineProperty(iframeWin.document, 'visibilityState', { get: () => 'visible' });
                            Object.defineProperty(iframeWin.document, 'hidden', { get: () => false });
                        } catch(e) {}

                        var bnsiData = null;
                        var capturedHeaders = {};
                        var isDone = false;
                        var lastM3u8Url = null;

                        var _pushHdrTimer = null;
                        function schedulePushStreamHeaders() {
                            if (!isDone) return;
                            if (_pushHdrTimer) clearTimeout(_pushHdrTimer);
                            _pushHdrTimer = setTimeout(function() {
                                _pushHdrTimer = null;
                                try { AndroidBridge.onStreamHeaders(JSON.stringify(capturedHeaders)); } catch(e) {}
                            }, 40);
                        }

                        function putHeader(name, value) {
                            if (!name || !value) return;
                            capturedHeaders[String(name).toLowerCase()] = String(value);
                            schedulePushStreamHeaders();
                        }

                        function checkDone() {
                            if (isDone) return;
                            var hasAuth = false, hasAccept = false, hasMaster = !!lastM3u8Url;
                            for (var k in capturedHeaders) {
                                if (k === 'authorizations') hasAuth = true;
                                if (k === 'authorization') hasAuth = true;
                                if (k === 'accepts-controls') hasAccept = true;
                            }
                            if (bnsiData && hasAuth && (hasAccept || hasMaster)) {
                                isDone = true;
                                try { AndroidBridge.onLog('ready: auth=' + hasAuth + ' accept=' + hasAccept + ' master=' + hasMaster); } catch(e) {}
                                AndroidBridge.onReady(bnsiData, JSON.stringify(capturedHeaders));
                            }
                        }

                        putHeader('origin', iframeWin.location.origin);
                        putHeader('referer', iframeWin.location.origin + '/');
                        putHeader('user-agent', iframeWin.navigator.userAgent);
                        putHeader('accept', '*/*');
                        putHeader('sec-fetch-dest', 'empty');
                        putHeader('sec-fetch-mode', 'cors');
                        putHeader('sec-fetch-site', 'cross-site');

                        var originalOpen = iframeWin.XMLHttpRequest.prototype.open;
                        iframeWin.XMLHttpRequest.prototype.open = function(method, url) {
                            this._allohaUrl = url;
                            this.addEventListener('load', function() {
                                var rUrl = this.responseURL || '';
                                if (rUrl.indexOf('/bnsi/') !== -1 && !isDone) {
                                    bnsiData = this.responseText;
                                    checkDone();
                                }
                                if (isDone && rUrl.indexOf('master.m3u8') !== -1 && rUrl !== lastM3u8Url) {
                                    lastM3u8Url = rUrl;
                                    try { AndroidBridge.onM3u8Refreshed(rUrl, JSON.stringify(capturedHeaders)); } catch(e) {}
                                }
                            });
                            originalOpen.apply(this, arguments);
                        };

                        var originalSetHeader = iframeWin.XMLHttpRequest.prototype.setRequestHeader;
                        iframeWin.XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
                            putHeader(name, value);
                            var url = this._allohaUrl || '';
                            if (url.indexOf('.m3u8') !== -1 || url.indexOf('.ts') !== -1) { checkDone(); }
                            return originalSetHeader.apply(this, arguments);
                        };

                        var _fallbackHost = null;
                        var _primaryHost = null;
                        var _fallbackMasterUrl = null;
                        function extractFallbackHost() {
                            if (_fallbackHost || !bnsiData) return;
                            try {
                                var d = JSON.parse(bnsiData);
                                var src = d.hlsSource;
                                if (src && src[0] && src[0].quality) {
                                    var q = src[0].quality;
                                    var key = Object.keys(q)[0];
                                    var urls = q[key].split(' or ');
                                    if (urls.length > 1) {
                                        var m = urls[0].match(/https?:\\/\\/([^\\/]+)/);
                                        if (m) _primaryHost = m[1];
                                        var fb = urls[1].trim();
                                        var m2 = fb.match(/https?:\\/\\/([^\\/]+)/);
                                        if (m2) { _fallbackHost = m2[1]; _fallbackMasterUrl = fb; }
                                    }
                                }
                            } catch(e) {}
                        }

                        var originalFetch = iframeWin.fetch;
                        iframeWin.fetch = function(input, init) {
                            try {
                                var url = (typeof input === 'string') ? input : (input && input.url ? input.url : '');
                                if (init && init.headers) {
                                    if (typeof init.headers.forEach === 'function') {
                                        init.headers.forEach(function(v, k) { putHeader(k, v); });
                                    } else {
                                        for (var hk in init.headers) { putHeader(hk, init.headers[hk]); }
                                    }
                                }
                                if (url && (url.indexOf('.m3u8') !== -1 || url.indexOf('.ts') !== -1)) {
                                    checkDone();
                                    extractFallbackHost();
                                    if (_primaryHost && _fallbackHost && url.indexOf(_primaryHost) !== -1) {
                                        var self = this;
                                        var fallbackUrl = (url.indexOf('master.m3u8') !== -1 && _fallbackMasterUrl)
                                            ? _fallbackMasterUrl : url.replace(_primaryHost, _fallbackHost);
                                        return originalFetch.apply(self, [input, init]).then(function(resp) {
                                            if (resp.status === 500 || resp.status === 503 || resp.status === 403) {
                                                return originalFetch.apply(iframeWin, [fallbackUrl, init]);
                                            }
                                            return resp;
                                        });
                                    }
                                }
                            } catch(e) {}
                            return originalFetch.apply(this, arguments);
                        };

                        var _origSend = iframeWin.WebSocket.prototype.send;
                        var _allohaWs = null;
                        var _heartbeatTimer = null;
                        var _sessionStart = Date.now();
                        var _lastEdgeHash = null;

                        function startHeartbeat(ws) {
                            if (_heartbeatTimer) clearInterval(_heartbeatTimer);
                            _heartbeatTimer = setInterval(function() {
                                if (!isDone) return;
                                if (!ws || ws.readyState !== 1) return;
                                var t = Math.floor((Date.now() - _sessionStart) / 1000);
                                try {
                                    _origSend.call(ws, JSON.stringify({
                                        type: 'playing', current_time: t, resolution: '1080',
                                        track_id: '1', speed: 1, subtitle: 0, ts: Date.now()
                                    }));
                                } catch(e) {}
                            }, 25000);
                        }

                        iframeWin.WebSocket.prototype.send = function(data) {
                            if (!this.__alloha_hooked) {
                                this.__alloha_hooked = true;
                                var ws = this;
                                _allohaWs = ws;
                                _sessionStart = Date.now();
                                ws.addEventListener('message', function(event) {
                                    try {
                                        var msg = JSON.parse(event.data);
                                        if (msg && msg.type === 'config_update' && msg.edge_hash) {
                                            if (msg.edge_hash !== _lastEdgeHash) {
                                                _lastEdgeHash = msg.edge_hash;
                                                var ttl = msg.ttl || 120;
                                                capturedHeaders['accepts-controls'] = msg.edge_hash;
                                                AndroidBridge.onConfigUpdate(msg.edge_hash, ttl, JSON.stringify(capturedHeaders));
                                            }
                                        }
                                    } catch(e) {}
                                });
                                ws.addEventListener('close', function(e) {
                                    if (_allohaWs === ws) { _allohaWs = null; if (_heartbeatTimer) clearInterval(_heartbeatTimer); }
                                });
                                startHeartbeat(ws);
                            }
                            return _origSend.call(this, data);
                        };

                        var OrigWS = iframeWin.WebSocket;
                        iframeWin.WebSocket = function(url, protocols) {
                            return protocols ? new OrigWS(url, protocols) : new OrigWS(url);
                        };
                        iframeWin.WebSocket.prototype = OrigWS.prototype;
                        iframeWin.WebSocket.CONNECTING = OrigWS.CONNECTING;
                        iframeWin.WebSocket.OPEN = OrigWS.OPEN;
                        iframeWin.WebSocket.CLOSING = OrigWS.CLOSING;
                        iframeWin.WebSocket.CLOSED = OrigWS.CLOSED;

                        setInterval(function() {
                            if (!isDone) {
                                var playBtn = iframeWin.document.querySelector('.allplay__play-btn');
                                if (playBtn) playBtn.click();
                                var video = iframeWin.document.querySelector('video');
                                if (video) { video.muted = true; if (video.paused) video.play().catch(function(){}); }
                                try { checkDone(); } catch(e) {}
                            }
                        }, 1500);

                    } catch(e) { AndroidBridge.onLog('JS Error: ' + e); }
                };
            </script>
        </body>
        </html>
        """
    }
}
