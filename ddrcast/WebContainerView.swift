import SwiftUI
import WebKit

/// Hosts a tab's existing `WKWebView` without owning or resizing it for overlays.
struct WebContainerView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> UIView {
        let box = UIView()
        box.backgroundColor = UIColor(red: 0.043, green: 0.071, blue: 0.125, alpha: 1)
        box.clipsToBounds = true
        return box
    }

    func updateUIView(_ box: UIView, context: Context) {
        if webView.superview !== box {
            for sub in box.subviews { sub.removeFromSuperview() }
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            webView.frame = box.bounds
            box.addSubview(webView)
        } else if webView.frame != box.bounds {
            webView.frame = box.bounds
        }
    }
}
