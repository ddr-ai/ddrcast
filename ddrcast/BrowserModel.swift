import Combine
import Foundation
import SwiftUI
import WebKit

@MainActor
final class BrowserModel: ObservableObject {
    let processPool = WKProcessPool()

    @Published private(set) var tabs: [BrowserTab] = []
    @Published var selectedID: UUID

    private var tabObservers: [UUID: AnyCancellable] = [:]

    var selected: BrowserTab {
        tabs.first(where: { $0.id == selectedID }) ?? tabs[0]
    }

    var recommended: CastCandidate? { selected.tappedVideo?.candidate }
    var canGoBack: Bool { selected.canGoBack }
    var canGoForward: Bool { selected.canGoForward }
    var isLoading: Bool { selected.isLoading }
    var progress: Double { selected.progress }
    var candidates: [CastCandidate] {
        if let item = selected.tappedVideo?.candidate { return [item] }
        if AddressParser.isDirectMediaURL(selected.currentURL) {
            return [CastCandidate(
                id: selected.currentURL.absoluteString,
                title: selected.pageTitle,
                url: selected.currentURL,
                mime: AddressParser.mimeType(for: selected.currentURL),
                startTime: 0,
                sourceLabel: "Direct video URL",
                reliability: 100,
                recommended: true
            )]
        }
        return []
    }

    var lastLoadError: String? {
        get { selected.lastLoadError }
        set { selected.lastLoadError = newValue }
    }

    var addressBinding: Binding<String> {
        Binding(
            get: { self.selected.addressText },
            set: { self.selected.addressText = $0 }
        )
    }

    init() {
        let first = BrowserTab(processPool: processPool)
        tabs = [first]
        selectedID = first.id
        first.owner = self
        observe(first)
        first.loadHome()
    }

    func newTab(loading url: URL? = nil) {
        let tab = BrowserTab(processPool: processPool)
        tab.owner = self
        tabs.append(tab)
        observe(tab)
        selectedID = tab.id
        if let url, url.scheme != "ddrcast" {
            tab.load(url)
        } else {
            tab.loadHome()
        }
    }

    func closeTab(_ id: UUID) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else {
            selected.loadHome()
            selected.dismissCapturedVideo()
            return
        }
        let closing = tabs[index]
        closing.shutdown()
        tabObservers[id] = nil
        tabs.remove(at: index)
        if selectedID == id {
            let next = tabs[min(index, tabs.count - 1)]
            selectedID = next.id
        }
    }

    func select(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    func submitAddress() { selected.submitAddress() }
    func loadHome() { selected.loadHome() }
    func goBack() { selected.goBack() }
    func goForward() { selected.goForward() }

    fileprivate func openInNewTab(_ url: URL) {
        newTab(loading: url)
    }

    private func observe(_ tab: BrowserTab) {
        tabObservers[tab.id] = tab.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }
}

@MainActor
final class BrowserTab: NSObject, ObservableObject, Identifiable {
    let id = UUID()
    let webView: WKWebView
    weak var owner: BrowserModel?

    @Published var addressText = ""
    @Published var pageTitle = "New Tab"
    @Published var currentURL: URL = AddressParser.homeURL
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var progress: Double = 0
    @Published var isLoading = false
    @Published var lastLoadError: String?
    @Published var tappedVideo: TappedVideo?
    @Published var sourcePanelOpen = false
    @Published var hasCapturedSource = false

    private let messageProxy: ScriptMessageProxy
    private var observing = false

    var tabTitle: String {
        if currentURL.scheme == "ddrcast" { return "Home" }
        if !pageTitle.isEmpty && pageTitle != "New Tab" { return pageTitle }
        return AddressParser.displayHost(for: currentURL)
    }

    init(processPool: WKProcessPool) {
        let proxy = ScriptMessageProxy()
        messageProxy = proxy

        let controller = WKUserContentController()
        controller.addUserScript(
            WKUserScript(
                source: VideoDetector.tapScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        controller.add(proxy, name: VideoDetector.messageHandlerName)

        let config = WKWebViewConfiguration()
        config.processPool = processPool
        config.userContentController = controller
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = false
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.backgroundColor = UIColor(red: 0.043, green: 0.071, blue: 0.125, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.isOpaque = false
        self.webView = webView
        super.init()
        proxy.tab = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        startObserving()
    }

    func submitAddress() {
        load(AddressParser.resolve(addressText))
    }

    func load(_ url: URL) {
        lastLoadError = nil
        currentURL = url
        if url.scheme == "ddrcast" {
            loadHome()
            return
        }
        addressText = url.absoluteString
        webView.load(URLRequest(url: url))
    }

    func loadHome() {
        currentURL = AddressParser.homeURL
        addressText = ""
        pageTitle = "Home"
        lastLoadError = nil
        if let path = Bundle.main.path(forResource: "Home", ofType: "html") {
            let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
            webView.loadFileURL(URL(fileURLWithPath: path), allowingReadAccessTo: dir)
        } else {
            webView.loadHTMLString(
                "<html><body style='background:#0b1220;color:#e8eef7;font-family:-apple-system;padding:24px'><h1>ddrcast</h1><p>Search or enter a URL in the bar above.</p></body></html>",
                baseURL: nil
            )
        }
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    func toggleSourcePanel() {
        guard hasCapturedSource else { return }
        sourcePanelOpen.toggle()
    }

    func dismissCapturedVideo() {
        sourcePanelOpen = false
        hasCapturedSource = false
        tappedVideo = nil
    }

    func applyTappedVideo(_ raw: Any) {
        guard let tapped = VideoDetector.parseTapped(raw) else { return }
        tappedVideo = tapped
        hasCapturedSource = true
        sourcePanelOpen = true
    }

    func shutdown() {
        stopObserving()
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: VideoDetector.messageHandlerName
        )
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    private func startObserving() {
        guard !observing else { return }
        observing = true
        webView.addObserver(self, forKeyPath: "estimatedProgress", options: .new, context: nil)
        webView.addObserver(self, forKeyPath: "canGoBack", options: .new, context: nil)
        webView.addObserver(self, forKeyPath: "canGoForward", options: .new, context: nil)
        webView.addObserver(self, forKeyPath: "title", options: .new, context: nil)
        webView.addObserver(self, forKeyPath: "URL", options: .new, context: nil)
    }

    private func stopObserving() {
        guard observing else { return }
        observing = false
        webView.removeObserver(self, forKeyPath: "estimatedProgress")
        webView.removeObserver(self, forKeyPath: "canGoBack")
        webView.removeObserver(self, forKeyPath: "canGoForward")
        webView.removeObserver(self, forKeyPath: "title")
        webView.removeObserver(self, forKeyPath: "URL")
    }

    nonisolated override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        Task { @MainActor in
            switch keyPath {
            case "estimatedProgress":
                self.progress = self.webView.estimatedProgress
                self.isLoading = self.webView.estimatedProgress > 0 && self.webView.estimatedProgress < 1
            case "canGoBack":
                self.canGoBack = self.webView.canGoBack
            case "canGoForward":
                self.canGoForward = self.webView.canGoForward
            case "title":
                if let title = self.webView.title, !title.isEmpty { self.pageTitle = title }
            case "URL":
                if let url = self.webView.url {
                    if url.isFileURL {
                        self.currentURL = AddressParser.homeURL
                        if self.addressText.isEmpty || AddressParser.resolve(self.addressText) == AddressParser.homeURL {
                            self.addressText = ""
                        }
                    } else {
                        self.currentURL = url
                        self.addressText = url.absoluteString
                    }
                }
            default:
                break
            }
        }
    }

}

extension BrowserTab: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        lastLoadError = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        progress = 1
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

extension BrowserTab: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            owner?.openInNewTab(url)
        }
        return nil
    }
}

final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var tab: BrowserTab?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let body = message.body
        Task { @MainActor in
            self.tab?.applyTappedVideo(body)
        }
    }
}
