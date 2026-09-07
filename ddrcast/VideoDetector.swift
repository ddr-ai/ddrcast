import Foundation

struct DetectedVideo: Identifiable, Equatable {
    let id: String
    var title: String
    var pageURL: String
    var urls: [URL]
    var mime: String
    var currentTime: TimeInterval
    var duration: TimeInterval
    var playing: Bool
    var width: Int
    var height: Int
    var kind: String
    var castable: Bool
    var blockReason: String?

    var primaryURL: URL? { urls.first }
}

struct CastCandidate: Identifiable, Equatable {
    let id: String
    let title: String
    let url: URL
    let mime: String
    let startTime: TimeInterval
    let sourceLabel: String
    let reliability: Int
    let recommended: Bool
}

enum VideoDetector {
    static let messageHandlerName = "ddrcast"

    /// Injected at document end. Reports `<video>` tags, `<source>` children, and og:video.
    static let userScript = """
    (function() {
      if (window.__ddrcastInstalled) return;
      window.__ddrcastInstalled = true;

      function abs(u) {
        try { return new URL(u, document.baseURI).href; } catch (e) { return null; }
      }
      function isDirect(u) {
        if (!u) return false;
        if (u.indexOf('blob:') === 0 || u.indexOf('mediasource:') === 0 || u.indexOf('data:') === 0) return false;
        return u.indexOf('http://') === 0 || u.indexOf('https://') === 0;
      }
      function collect() {
        const items = [];
        const seen = {};
        function push(item) {
          const raw = (item.urls || []).map(abs).filter(Boolean);
          const direct = raw.filter(isDirect);
          const key = (direct[0] || raw[0] || item.title || '') + '|' + (item.kind || '');
          if (seen[key]) return;
          seen[key] = true;
          let reason = null;
          if (!direct.length) {
            if (raw.some(function(u) { return u.indexOf('blob:') === 0; })) {
              reason = 'blob-url';
            } else {
              reason = 'no-direct-url';
            }
          }
          items.push({
            title: item.title || document.title || 'Video',
            pageURL: location.href,
            urls: direct,
            mime: item.mime || '',
            currentTime: item.currentTime || 0,
            duration: item.duration || 0,
            playing: !!item.playing,
            width: item.width || 0,
            height: item.height || 0,
            kind: item.kind || 'video-element',
            castable: direct.length > 0,
            blockReason: reason
          });
        }
        document.querySelectorAll('video').forEach(function(v, i) {
          const urls = [];
          if (v.currentSrc) urls.push(v.currentSrc);
          if (v.src) urls.push(v.src);
          v.querySelectorAll('source').forEach(function(s) {
            if (s.src) urls.push(s.src);
          });
          const srcEl = v.querySelector('source');
          push({
            title: v.getAttribute('title') || v.getAttribute('aria-label') || document.title || ('Video ' + (i + 1)),
            urls: urls,
            mime: (srcEl && srcEl.getAttribute('type')) || '',
            currentTime: Number.isFinite(v.currentTime) ? v.currentTime : 0,
            duration: Number.isFinite(v.duration) ? v.duration : 0,
            playing: !v.paused && !v.ended,
            width: v.videoWidth || 0,
            height: v.videoHeight || 0,
            kind: 'video-element'
          });
        });
        const og = document.querySelector('meta[property="og:video"], meta[property="og:video:url"], meta[property="og:video:secure_url"]');
        if (og && og.content) {
          push({
            title: document.title || 'Page video',
            urls: [og.content],
            kind: 'og-video'
          });
        }
        const payload = {
          type: 'videos',
          pageURL: location.href,
          title: document.title,
          videos: items
        };
        try {
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.ddrcast) {
            window.webkit.messageHandlers.ddrcast.postMessage(payload);
          }
        } catch (e) {}
        return payload;
      }
      collect();
      const mo = new MutationObserver(function() { collect(); });
      mo.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['src'] });
      document.addEventListener('play', collect, true);
      document.addEventListener('loadedmetadata', collect, true);
    })();
    """

    static func parseVideos(_ raw: Any) -> [DetectedVideo] {
        let dict: [String: Any]
        if let d = raw as? [String: Any] {
            dict = d
        } else if let arr = raw as? [[String: Any]] {
            dict = ["videos": arr]
        } else {
            return []
        }
        let list = (dict["videos"] as? [[String: Any]]) ?? []
        return list.enumerated().map { index, item in
            let urlStrings = (item["urls"] as? [String]) ?? []
            let urls = urlStrings.compactMap { URL(string: $0) }
            let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return DetectedVideo(
                id: "\(index)-\(urls.first?.absoluteString ?? title ?? "v")",
                title: (title?.isEmpty == false ? title! : "Video \(index + 1)"),
                pageURL: item["pageURL"] as? String ?? "",
                urls: urls,
                mime: item["mime"] as? String ?? "",
                currentTime: (item["currentTime"] as? Double) ?? 0,
                duration: (item["duration"] as? Double) ?? 0,
                playing: item["playing"] as? Bool ?? false,
                width: item["width"] as? Int ?? 0,
                height: item["height"] as? Int ?? 0,
                kind: item["kind"] as? String ?? "video-element",
                castable: (item["castable"] as? Bool) ?? !urls.isEmpty,
                blockReason: item["blockReason"] as? String
            )
        }
    }

    static func candidates(pageURL: URL?, pageTitle: String, videos: [DetectedVideo]) -> [CastCandidate] {
        var items: [CastCandidate] = []
        if let pageURL, AddressParser.isDirectMediaURL(pageURL) {
            items.append(
                CastCandidate(
                    id: "page-\(pageURL.absoluteString)",
                    title: pageTitle.isEmpty ? pageURL.lastPathComponent : pageTitle,
                    url: pageURL,
                    mime: AddressParser.mimeType(for: pageURL),
                    startTime: 0,
                    sourceLabel: "Direct video URL",
                    reliability: 100,
                    recommended: false
                )
            )
        }
        for video in videos where video.castable {
            guard let url = video.primaryURL else { continue }
            var score = 70
            if video.kind == "video-element" { score = 80 }
            if video.playing { score += 10 }
            if AddressParser.isDirectMediaURL(url) { score += 5 }
            let mime = video.mime.isEmpty ? AddressParser.mimeType(for: url) : video.mime
            let label: String
            if video.kind == "og-video" {
                label = "Open Graph video"
            } else if video.playing {
                label = "Playing <video> source"
            } else {
                label = "Extracted <video> source"
            }
            items.append(
                CastCandidate(
                    id: video.id,
                    title: video.title,
                    url: url,
                    mime: mime,
                    startTime: video.currentTime,
                    sourceLabel: label,
                    reliability: score,
                    recommended: false
                )
            )
        }
        items.sort { $0.reliability > $1.reliability }
        var seen = Set<String>()
        items = items.filter { item in
            if seen.contains(item.url.absoluteString) { return false }
            seen.insert(item.url.absoluteString)
            return true
        }
        if let best = items.first {
            items[0] = CastCandidate(
                id: best.id,
                title: best.title,
                url: best.url,
                mime: best.mime,
                startTime: best.startTime,
                sourceLabel: best.sourceLabel,
                reliability: best.reliability,
                recommended: true
            )
        }
        return items
    }

    static func pageCastBlockReason(pageURL: URL?, videos: [DetectedVideo], candidates: [CastCandidate]) -> String? {
        if !candidates.isEmpty { return nil }
        if let pageURL, isLikelyDRMHost(pageURL) {
            return """
            This site does not expose a direct media URL the Chromecast Default Media Receiver can play (often DRM or encrypted streams). \
            ddrcast will not switch to screen mirroring. Casting the webpage itself would need a custom Cast receiver app, which is not configured.
            """
        }
        if videos.contains(where: { $0.blockReason == "blob-url" }) {
            return """
            The video on this page uses a blob: or Media Source URL, which cannot be sent to a Chromecast. \
            ddrcast will not fall back to screen mirroring. A custom receiver is not configured.
            """
        }
        if !videos.isEmpty {
            return """
            Videos were found on this page but none have a direct http(s) media URL the Default Media Receiver can load. \
            Screen mirroring is not used.
            """
        }
        return """
        No castable video was found on this page. Enter a direct media URL (mp4, HLS / m3u8, webm) or open a page whose <video> tag has a real source URL.
        """
    }

    static func isLikelyDRMHost(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        let hosts = [
            "youtube.com", "youtu.be", "netflix.com", "disneyplus.com", "hulu.com",
            "primevideo.com", "amazon.com", "max.com", "hbomax.com", "paramountplus.com",
            "peacocktv.com", "apple.com", "tv.apple.com", "play.google.com",
        ]
        return hosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }
}
