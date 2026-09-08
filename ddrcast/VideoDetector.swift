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

struct TappedVideo: Equatable {
    var title: String
    var pageURL: String
    var contentURLs: [URL]
    var adURLs: [URL]
    var preferredURL: URL?
    var hasAd: Bool
    var waitingForContent: Bool
    var currentTime: TimeInterval
    var duration: TimeInterval
    var mime: String
    var playing: Bool

    var displayURL: URL? { preferredURL ?? contentURLs.last ?? contentURLs.first }

    var candidate: CastCandidate? {
        guard let url = displayURL else { return nil }
        let label: String
        if hasAd, !waitingForContent {
            label = "Content source (ad skipped)"
        } else if AddressParser.isDirectMediaURL(url) {
            label = "Direct media URL"
        } else {
            label = "Tapped video source"
        }
        return CastCandidate(
            id: url.absoluteString,
            title: title,
            url: url,
            mime: mime.isEmpty ? AddressParser.mimeType(for: url) : mime,
            startTime: 0,
            sourceLabel: label,
            reliability: hasAd ? 95 : 90,
            recommended: true
        )
    }
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

    /// Runs in every frame. Does nothing until the user taps/clicks a video
    /// (or its play control). Then it watches only that element so preroll ads
    /// can be replaced by the content source.
    static let tapScript = #"""
    (function() {
      if (window.__ddrcastTapInstalled) return;
      window.__ddrcastTapInstalled = true;

      var watched = null;
      var extra = [];

      function post(payload) {
        try {
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.ddrcast) {
            window.webkit.messageHandlers.ddrcast.postMessage(payload);
          }
        } catch (e) {}
      }
      function abs(u) {
        try { return new URL(u, document.baseURI).href; } catch (e) { return null; }
      }
      function isDirect(u) {
        if (!u) return false;
        if (u.indexOf('blob:') === 0 || u.indexOf('mediasource:') === 0 || u.indexOf('data:') === 0) return false;
        return u.indexOf('http://') === 0 || u.indexOf('https://') === 0;
      }
      function isAd(u) {
        if (!u) return false;
        var s = String(u).toLowerCase();
        return /doubleclick|googlesyndication|googleadservices|googletagservices|pagead|adsystem|adsrvr|adnxs|adservice|adserver|\/ads\/|\/ad\/|preroll|midroll|vast|vmap|ima3|spotx|moatads|pubmatic|advertising|ad-break|adbreak/.test(s);
      }
      function looksMedia(u) {
        if (!u) return false;
        var s = String(u).split('?')[0].toLowerCase();
        return /\.(mp4|m4v|m3u8|mpd|webm|mov|mkv)(\b|$)/.test(s)
          || s.indexOf('m3u8') !== -1
          || s.indexOf('/video') !== -1
          || /mime=video|content-type=video/.test(String(u).toLowerCase());
      }
      function fromVideo(v) {
        var urls = [];
        if (v.currentSrc) urls.push(v.currentSrc);
        if (v.src) urls.push(v.src);
        var sources = v.querySelectorAll('source');
        for (var i = 0; i < sources.length; i++) {
          if (sources[i].src) urls.push(sources[i].src);
        }
        return urls;
      }
      function report(v) {
        var raw = fromVideo(v).concat(extra);
        var direct = [];
        var seen = {};
        for (var i = 0; i < raw.length; i++) {
          var u = abs(raw[i]);
          if (!u || !isDirect(u) || seen[u]) continue;
          seen[u] = true;
          direct.push(u);
        }
        var content = [];
        var ads = [];
        for (var j = 0; j < direct.length; j++) {
          if (isAd(direct[j])) ads.push(direct[j]);
          else content.push(direct[j]);
        }
        var preferred = null;
        if (content.length) {
          preferred = content[content.length - 1];
        }
        var dur = Number.isFinite(v.duration) ? v.duration : 0;
        if (!preferred && ads.length && dur > 0 && dur < 45) {
          preferred = null;
        }
        post({
          type: 'tapped-video',
          title: v.getAttribute('title') || v.getAttribute('aria-label') || document.title || 'Video',
          pageURL: location.href,
          urls: content.length ? content : direct,
          adUrls: ads,
          preferredURL: preferred,
          hasAd: ads.length > 0,
          waitingForContent: ads.length > 0 && content.length === 0,
          currentTime: Number.isFinite(v.currentTime) ? v.currentTime : 0,
          duration: dur,
          mime: '',
          playing: !v.paused && !v.ended
        });
      }
      function unwatch() {
        if (!watched) return;
        var v = watched;
        if (v.__ddrcastOnSrc) {
          v.removeEventListener('loadedmetadata', v.__ddrcastOnSrc);
          v.removeEventListener('durationchange', v.__ddrcastOnSrc);
          v.removeEventListener('play', v.__ddrcastOnSrc);
          v.removeEventListener('emptied', v.__ddrcastOnSrc);
        }
        if (v.__ddrcastMO) v.__ddrcastMO.disconnect();
        if (v.__ddrcastPO) { try { v.__ddrcastPO.disconnect(); } catch (e) {} }
        watched = null;
        extra = [];
      }
      function watchVideo(v) {
        if (!v) return;
        if (watched !== v) {
          unwatch();
          watched = v;
          extra = [];
          var onSrc = function() { report(v); };
          v.__ddrcastOnSrc = onSrc;
          v.addEventListener('loadedmetadata', onSrc);
          v.addEventListener('durationchange', onSrc);
          v.addEventListener('play', onSrc);
          v.addEventListener('emptied', onSrc);
          var mo = new MutationObserver(onSrc);
          mo.observe(v, { attributes: true, attributeFilter: ['src'] });
          var sources = v.querySelectorAll('source');
          for (var i = 0; i < sources.length; i++) {
            mo.observe(sources[i], { attributes: true, attributeFilter: ['src'] });
          }
          v.__ddrcastMO = mo;
          try {
            var po = new PerformanceObserver(function(list) {
              var entries = list.getEntries();
              for (var k = 0; k < entries.length; k++) {
                var n = entries[k].name;
                if (isDirect(n) && looksMedia(n) && !isAd(n)) {
                  extra.push(n);
                  report(v);
                }
              }
            });
            po.observe({ type: 'resource', buffered: true });
            v.__ddrcastPO = po;
          } catch (e) {}
        }
        report(v);
      }
      function videoFromEvent(t) {
        if (!t) return null;
        if (t.tagName === 'VIDEO') return t;
        if (t.closest) {
          var v = t.closest('video');
          if (v) return v;
          var root = t.closest('figure, [class*="player"], [class*="video"], [id*="player"], [id*="video"]');
          if (root && root.querySelector) {
            var inner = root.querySelector('video');
            if (inner) return inner;
          }
        }
        return null;
      }
      document.addEventListener('click', function(ev) {
        var v = videoFromEvent(ev.target);
        if (v) watchVideo(v);
      }, true);
      document.addEventListener('touchend', function(ev) {
        if (!ev.changedTouches || !ev.changedTouches.length) return;
        var n = document.elementFromPoint(ev.changedTouches[0].clientX, ev.changedTouches[0].clientY);
        var v = videoFromEvent(n);
        if (v) watchVideo(v);
      }, true);
    })();
    """#

    static func parseTapped(_ raw: Any) -> TappedVideo? {
        guard let dict = raw as? [String: Any] else { return nil }
        let type = dict["type"] as? String
        if let type, type != "tapped-video" { return nil }
        func urls(_ key: String) -> [URL] {
            ((dict[key] as? [String]) ?? []).compactMap { URL(string: $0) }
        }
        let content = urls("urls").filter { !AddressParser.isLikelyAdURL($0) }
        let ads = urls("adUrls") + urls("urls").filter { AddressParser.isLikelyAdURL($0) }
        let preferred = (dict["preferredURL"] as? String).flatMap(URL.init(string:))
            ?? content.last
        let title = (dict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return TappedVideo(
            title: (title?.isEmpty == false ? title! : "Video"),
            pageURL: dict["pageURL"] as? String ?? "",
            contentURLs: content,
            adURLs: ads,
            preferredURL: preferred.flatMap { AddressParser.isLikelyAdURL($0) ? content.last : $0 } ?? content.last,
            hasAd: (dict["hasAd"] as? Bool) ?? !ads.isEmpty,
            waitingForContent: (dict["waitingForContent"] as? Bool) ?? (content.isEmpty && !ads.isEmpty),
            currentTime: (dict["currentTime"] as? Double) ?? 0,
            duration: (dict["duration"] as? Double) ?? 0,
            mime: dict["mime"] as? String ?? "",
            playing: dict["playing"] as? Bool ?? false
        )
    }
}
