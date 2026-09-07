import Combine
import Foundation
import WebKit


@MainActor
final class BrowserModel: NSObject, ObservableObject {
    @Published var addressText = ""
    @Published var pageTitle = "ddrcast"
    @Published var currentURL: URL = AddressParser.homeURL
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var progress: Double = 0
    @Published var isLoading = false
    @Published var videos: [DetectedVideo] = []
    @Published var candidates: [CastCandidate] = []
    @Published var pageBlockReason: String?
    @Published var lastLoadError: String?

    weak var webView: WKWebView?
    private var observing = false
    private var didLoadInitial = false

    var recommended: CastCandidate? { candidates.first { $0.recommended } ?? candidates.first }

    func attach(_ webView: WKWebView) {
        if observing, let old = self.webView, old !== webView {
            detach(old)
        }
        self.webView = webView
        webView.navigationDelegate = self
        webView.uiDelegate = self
        if !observing {
            webView.addObserver(self, forKeyPath: "estimatedProgress", options: .new, context: nil)
            webView.addObserver(self, forKeyPath: "canGoBack", options: .new, context: nil)
            webView.addObserver(self, forKeyPath: "canGoForward", options: .new, context: nil)
            webView.addObserver(self, forKeyPath: "title", options: .new, context: nil)
            webView.addObserver(self, forKeyPath: "URL", options: .new, context: nil)
            observing = true
        }
        if !didLoadInitial {
            didLoadInitial = true
            loadHome()
        }
    }

    func detach(_ webView: WKWebView) {
        if observing {
            webView.removeObserver(self, forKeyPath: "estimatedProgress")
            webView.removeObserver(self, forKeyPath: "canGoBack")
            webView.removeObserver(self, forKeyPath: "canGoForward")
            webView.removeObserver(self, forKeyPath: "title")
            webView.removeObserver(self, forKeyPath: "URL")
            observing = false
        }
        if self.webView === webView { self.webView = nil }
    }

    func submitAddress() {
        let url = AddressParser.resolve(addressText)
        load(url)
    }

    func load(_ url: URL) {
        lastLoadError = nil
        currentURL = url
        if url.scheme == "ddrcast" {
            loadHome()
            return
        }
        addressText = url.absoluteString
        webView?.load(URLRequest(url: url))
    }

    func loadHome() {
        currentURL = AddressParser.homeURL
        addressText = ""
        pageTitle = "ddrcast"
        videos = []
        candidates = []
        pageBlockReason = nil
        guard let webView else { return }
        if let path = Bundle.main.path(forResource: "Home", ofType: "html") {
            let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
            webView.loadFileURL(URL(fileURLWithPath: path), allowingReadAccessTo: dir)
        } else {
            webView.loadHTMLString(Self.fallbackHomeHTML, baseURL: nil)
        }
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }

    func refreshVideos() {
        webView?.evaluateJavaScript(VideoDetector.userScript, completionHandler: nil)
    }

    func applyVideoPayload(_ raw: Any) {
        let detected = VideoDetector.parseVideos(raw)
        videos = detected
        rebuildCandidates()
    }

    func rebuildCandidates() {
        let page = currentURL.scheme == "ddrcast" ? nil : currentURL
        candidates = VideoDetector.candidates(pageURL: page, pageTitle: pageTitle, videos: videos)
        pageBlockReason = VideoDetector.pageCastBlockReason(
            pageURL: page,
            videos: videos,
            candidates: candidates
        )
    }

    nonisolated override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        Task { @MainActor in
            guard let webView = self.webView else { return }
            switch keyPath {
            case "estimatedProgress":
                self.progress = webView.estimatedProgress
                self.isLoading = webView.estimatedProgress > 0 && webView.estimatedProgress < 1
            case "canGoBack":
                self.canGoBack = webView.canGoBack
            case "canGoForward":
                self.canGoForward = webView.canGoForward
            case "title":
                if let title = webView.title, !title.isEmpty { self.pageTitle = title }
            case "URL":
                if let url = webView.url {
                    if url.isFileURL {
                        self.currentURL = AddressParser.homeURL
                        if !self.addressText.isEmpty && AddressParser.resolve(self.addressText) != AddressParser.homeURL {
                            // keep typed text while home is loading
                        } else {
                            self.addressText = ""
                        }
                    } else {
                        self.currentURL = url
                        self.addressText = url.absoluteString
                    }
                    self.rebuildCandidates()
                }
            default:
                break
            }
        }
    }

    private static let fallbackHomeHTML = """
    <html><body style="background:#0b1220;color:#e8eef7;font-family:-apple-system;padding:24px">
    <h1>ddrcast</h1><p>Search or enter a URL in the bar above.</p></body></html>
    """
}

extension BrowserModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        lastLoadError = nil
        videos = []
        rebuildCandidates()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        progress = 1
        refreshVideos()
        rebuildCandidates()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        lastLoadError = error.localizedDescription
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        lastLoadError = error.localizedDescription
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url, url.scheme == "ddrcast" {
            loadHome()
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

extension BrowserModel: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}

