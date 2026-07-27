import SwiftUI
import WebKit

final class PlayerWebViewStore: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var currentURL: URL?
    @Published var pageTitle: String = ""

    let webView: WKWebView

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true
        // keep the real WebKit UA and just add the Safari token — a frozen
        // full-UA spoof trips YouTube's "An error occurred" playback check
        config.applicationNameForUserAgent = "Version/26.0 Mobile/15E148 Safari/604.1"

        // keep playing when the app is backgrounded: youtube pauses on
        // visibilitychange, so never let the page see one
        let visibilitySpoof = WKUserScript(source: """
            (function() {
              Object.defineProperty(document, 'hidden', {get: () => false});
              Object.defineProperty(document, 'visibilityState', {get: () => 'visible'});
              const stop = e => e.stopImmediatePropagation();
              for (const t of [document, window]) {
                t.addEventListener('visibilitychange', stop, true);
                t.addEventListener('webkitvisibilitychange', stop, true);
              }
              window.addEventListener('pagehide', stop, true);
              window.addEventListener('blur', stop, true);
            })();
            """, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(visibilitySpoof)

        // tap Skip the instant it appears; fast-forward unskippables; resume
        // if an ad left the player paused
        let adSkip = WKUserScript(source: """
            setInterval(() => {
              const skip = document.querySelector(
                '.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern, button[aria-label*="Skip"]');
              if (skip) skip.click();
              const close = document.querySelector('.ytp-ad-overlay-close-button');
              if (close) close.click();
              const v = document.querySelector('video');
              const inAd = document.querySelector('.ad-showing, .ad-interrupting');
              if (v && inAd && isFinite(v.duration) && v.duration > 0) {
                v.muted = true;
                v.currentTime = v.duration;   // jump to the end of the ad
              } else if (v) {
                v.muted = false;
              }
              if (v && v.paused && !v.ended && inAd) v.play();
            }, 700);
            """, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        config.userContentController.addUserScript(adSkip)

        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        super.init()
        webView.navigationDelegate = self
        installAdBlockRules()
        load(urlString: "https://m.youtube.com")
    }

    /// Block the common ad/tracker hosts at the network layer. YouTube streams
    /// its own ads from googlevideo.com so this can't catch everything — the
    /// skip/fast-forward script above handles those.
    private func installAdBlockRules() {
        let rules = """
        [
          {"trigger": {"url-filter": "doubleclick\\\\.net"}, "action": {"type": "block"}},
          {"trigger": {"url-filter": "googlesyndication\\\\.com"}, "action": {"type": "block"}},
          {"trigger": {"url-filter": "googleadservices\\\\.com"}, "action": {"type": "block"}},
          {"trigger": {"url-filter": "google-analytics\\\\.com"}, "action": {"type": "block"}},
          {"trigger": {"url-filter": "youtube\\\\.com/api/stats/ads"}, "action": {"type": "block"}},
          {"trigger": {"url-filter": "youtube\\\\.com/pagead"}, "action": {"type": "block"}},
          {"trigger": {"url-filter": "youtube\\\\.com/ptracking"}, "action": {"type": "block"}}
        ]
        """
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "partyhop-adblock", encodedContentRuleList: rules) { [weak self] list, _ in
            if let list {
                self?.webView.configuration.userContentController.add(list)
            }
        }
    }

    func load(urlString: String) {
        var s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        if !s.contains("://") {
            if s.contains(".") && !s.contains(" ") {
                s = "https://\(s)"
            } else {
                let q = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
                s = "https://m.youtube.com/results?search_query=\(q)"
            }
        }
        if let url = URL(string: s) {
            webView.load(URLRequest(url: url))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        currentURL = webView.url
        pageTitle = webView.title ?? ""
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        currentURL = webView.url
    }

    /// Best-effort current video URL: SPA navigations don't always hit the
    /// navigation delegate, so ask the page directly.
    func fetchVideoURL(completion: @escaping (String?) -> Void) {
        webView.evaluateJavaScript("window.location.href") { result, _ in
            let href = result as? String ?? self.webView.url?.absoluteString
            guard let href, href.contains("watch") || href.contains("youtu.be") else {
                completion(nil)
                return
            }
            completion(href)
        }
    }
}

struct PlayerWebView: UIViewRepresentable {
    @ObservedObject var store: PlayerWebViewStore

    func makeUIView(context: Context) -> WKWebView { store.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
