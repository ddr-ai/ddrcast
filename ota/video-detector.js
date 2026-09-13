(function() {
  var VERSION = 3;
  if (window.__ddrcastTapVersion >= VERSION) return;
  if (typeof window.__ddrcastTapCleanup === "function") {
    try { window.__ddrcastTapCleanup(); } catch (e) {}
  }
  window.__ddrcastTapVersion = VERSION;

  var watched = null;
  var extra = [];
  var clickHandler = null;
  var touchHandler = null;

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
    if (u.indexOf("blob:") === 0 || u.indexOf("mediasource:") === 0 || u.indexOf("data:") === 0) return false;
    return u.indexOf("http://") === 0 || u.indexOf("https://") === 0;
  }
  function isAd(u) {
    if (!u) return false;
    var s = String(u).toLowerCase();
    return /doubleclick|googlesyndication|googleadservices|googletagservices|pagead|adsystem|adsrvr|adnxs|adservice|adserver|\/ads\/|\/ad\/|preroll|midroll|vast|vmap|ima3|spotx|moatads|pubmatic|advertising|ad-break|adbreak/.test(s);
  }
  function looksMedia(u) {
    if (!u) return false;
    var s = String(u).split("?")[0].toLowerCase();
    return /\.(mp4|m4v|m3u8|mpd|webm|mov|mkv)(\b|$)/.test(s)
      || s.indexOf("m3u8") !== -1
      || s.indexOf("/video") !== -1
      || /mime=video|content-type=video/.test(String(u).toLowerCase());
  }
  function fromVideo(v) {
    var urls = [];
    if (v.currentSrc) urls.push(v.currentSrc);
    if (v.src) urls.push(v.src);
    var sources = v.querySelectorAll("source");
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
    var preferred = content.length ? content[content.length - 1] : null;
    var dur = Number.isFinite(v.duration) ? v.duration : 0;
    post({
      type: "tapped-video",
      title: v.getAttribute("title") || v.getAttribute("aria-label") || document.title || "Video",
      pageURL: location.href,
      urls: content.length ? content : direct,
      adUrls: ads,
      preferredURL: preferred,
      hasAd: ads.length > 0,
      waitingForContent: ads.length > 0 && content.length === 0,
      currentTime: Number.isFinite(v.currentTime) ? v.currentTime : 0,
      duration: dur,
      mime: "",
      playing: !v.paused && !v.ended
    });
  }
  function unwatch() {
    if (!watched) return;
    var v = watched;
    if (v.__ddrcastOnSrc) {
      v.removeEventListener("loadedmetadata", v.__ddrcastOnSrc);
      v.removeEventListener("durationchange", v.__ddrcastOnSrc);
      v.removeEventListener("play", v.__ddrcastOnSrc);
      v.removeEventListener("emptied", v.__ddrcastOnSrc);
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
      v.addEventListener("loadedmetadata", onSrc);
      v.addEventListener("durationchange", onSrc);
      v.addEventListener("play", onSrc);
      v.addEventListener("emptied", onSrc);
      var mo = new MutationObserver(onSrc);
      mo.observe(v, { attributes: true, attributeFilter: ["src"] });
      var sources = v.querySelectorAll("source");
      for (var i = 0; i < sources.length; i++) {
        mo.observe(sources[i], { attributes: true, attributeFilter: ["src"] });
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
        po.observe({ type: "resource", buffered: true });
        v.__ddrcastPO = po;
      } catch (e) {}
    }
    report(v);
  }
  function videoFromEvent(t) {
    if (!t) return null;
    if (t.tagName === "VIDEO") return t;
    if (t.closest) {
      var v = t.closest("video");
      if (v) return v;
      var root = t.closest('figure, [class*="player"], [class*="video"], [id*="player"], [id*="video"]');
      if (root && root.querySelector) {
        var inner = root.querySelector("video");
        if (inner) return inner;
      }
    }
    return null;
  }
  clickHandler = function(ev) {
    var v = videoFromEvent(ev.target);
    if (v) watchVideo(v);
  };
  touchHandler = function(ev) {
    if (!ev.changedTouches || !ev.changedTouches.length) return;
    var n = document.elementFromPoint(ev.changedTouches[0].clientX, ev.changedTouches[0].clientY);
    var v = videoFromEvent(n);
    if (v) watchVideo(v);
  };
  document.addEventListener("click", clickHandler, true);
  document.addEventListener("touchend", touchHandler, true);
  window.__ddrcastTapCleanup = function() {
    document.removeEventListener("click", clickHandler, true);
    document.removeEventListener("touchend", touchHandler, true);
    unwatch();
    window.__ddrcastTapVersion = 0;
  };
})();
