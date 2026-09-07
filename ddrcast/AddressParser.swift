import Foundation

enum AddressParser {
    static let homeURL = URL(string: "ddrcast://home")!
    static let searchHost = "duckduckgo.com"

    static let mediaExtensions: Set<String> = [
        "mp4", "m4v", "mov", "webm", "mkv", "avi", "ogv",
        "m3u8", "mpd", "ts",
        "mp3", "aac", "m4a", "flac", "wav", "ogg",
    ]

    static func resolve(_ raw: String) -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return homeURL }
        let lower = trimmed.lowercased()
        if lower == "ddrcast://home" || lower == "about:home" || lower == "about:blank" {
            return homeURL
        }
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return url
        }
        if looksLikeURL(trimmed), let url = URL(string: "https://\(trimmed)") {
            return url
        }
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = searchHost
        comps.path = "/"
        comps.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return comps.url ?? homeURL
    }

    static func looksLikeURL(_ s: String) -> Bool {
        if s.contains(" ") { return false }
        if s.lowercased().hasPrefix("localhost") { return true }
        if s.range(of: #"^\d{1,3}(\.\d{1,3}){3}(:\d+)?(/.*)?$"#, options: .regularExpression) != nil {
            return true
        }
        return s.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9\-\.]*\.[A-Za-z]{2,}(:\d+)?(/.*)?(\?.*)?$"#,
            options: .regularExpression
        ) != nil
    }

    static func isDirectMediaURL(_ url: URL) -> Bool {
        if url.scheme == "ddrcast" { return false }
        let ext = url.pathExtension.lowercased()
        if mediaExtensions.contains(ext) { return true }
        let path = url.path.lowercased()
        return path.contains(".m3u8") || path.contains(".mpd")
    }

    static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp4", "m4v": return "video/mp4"
        case "webm": return "video/webm"
        case "mkv": return "video/x-matroska"
        case "mov": return "video/quicktime"
        case "avi": return "video/x-msvideo"
        case "ogv", "ogg": return "video/ogg"
        case "m3u8": return "application/x-mpegURL"
        case "mpd": return "application/dash+xml"
        case "ts": return "video/mp2t"
        case "mp3": return "audio/mpeg"
        case "aac", "m4a": return "audio/mp4"
        case "flac": return "audio/flac"
        case "wav": return "audio/wav"
        default: return "video/mp4"
        }
    }

    static func displayHost(for url: URL?) -> String {
        guard let url else { return "" }
        if url.scheme == "ddrcast" { return "ddrcast" }
        return url.host ?? url.absoluteString
    }
}
