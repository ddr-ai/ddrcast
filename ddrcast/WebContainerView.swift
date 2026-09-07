import SwiftUI
import WebKit

struct WebContainerView: UIViewRepresentable {
    @EnvironmentObject var browser: BrowserModel

    func makeCoordinator() -> Coordinator {
        Coordinator(browser: browser)
    }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        let script = WKUserScript(
            source: VideoDetector.userScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        controller.addUserScript(script)
        controller.add(context.coordinator, name: VideoDetector.messageHandlerName)

        let config = WKWebViewConfiguration()
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
        context.coordinator.installed = webView
        browser.attach(webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: VideoDetector.messageHandlerName)
        coordinator.browser.detach(uiView)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let browser: BrowserModel
        var installed: WKWebView?
        init(browser: BrowserModel) { self.browser = browser }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            let body = message.body
            Task { @MainActor in
                self.browser.applyVideoPayload(body)
            }
        }
    }
}
