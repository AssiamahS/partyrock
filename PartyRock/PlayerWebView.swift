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
        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        super.init()
        webView.navigationDelegate = self
        load(urlString: "https://m.youtube.com")
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
