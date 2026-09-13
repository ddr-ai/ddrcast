import Combine
import Darwin
import Foundation
import Network

struct RokuDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let model: String
    let baseURL: URL
}

@MainActor
final class RokuService: ObservableObject {
    static let shared = RokuService()

    @Published private(set) var devices: [RokuDevice] = []
    @Published private(set) var isScanning = false

    private init() {}

    func scan() async {
        isScanning = true
        defer { isScanning = false }
        var found: [String: RokuDevice] = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })
        let hosts = localSubnetHosts()
        await withTaskGroup(of: RokuDevice?.self) { group in
            for host in hosts {
                group.addTask { await Self.probe(host: host) }
            }
            for await device in group {
                if let device { found[device.id] = device }
            }
        }
        devices = found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func play(on device: RokuDevice, url: URL, title: String) async throws {
        let format = Self.videoFormat(for: url)
        let ids = OTAUpdateService.shared.rokuAppIds
        var lastError: Error = RokuError.playFailed("No PlayOnRoku app id")
        for appId in ids {
            for path in ["launch", "input"] {
                do {
                    try await ecpPost(
                        device: device,
                        path: "\(path)/\(appId)",
                        query: [
                            "t": "v",
                            "u": url.absoluteString,
                            "videoName": title,
                            "videoFormat": format,
                        ]
                    )
                    return
                } catch {
                    lastError = error
                }
            }
        }
        if let discovered = try? await mediaAppId(on: device) {
            try await ecpPost(
                device: device,
                path: "launch/\(discovered)",
                query: [
                    "t": "v",
                    "u": url.absoluteString,
                    "videoName": title,
                    "videoFormat": format,
                ]
            )
            return
        }
        throw lastError
    }

    func keypress(_ key: String, on device: RokuDevice) async {
        try? await ecpPost(device: device, path: "keypress/\(key)", query: [:])
    }

    func sendText(_ text: String, on device: RokuDevice) async {
        for ch in text {
            if ch == "\n" {
                await keypress("Enter", on: device)
            } else if ch == "\u{8}" {
                await keypress("Backspace", on: device)
            } else {
                let raw = String(ch)
                let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? raw
                await keypress("Lit_\(encoded)", on: device)
            }
            try? await Task.sleep(nanoseconds: 35_000_000)
        }
    }

    func pause(on device: RokuDevice) async { await keypress("Pause", on: device) }
    func playPause(on device: RokuDevice) async { await keypress("Play", on: device) }
    func home(on device: RokuDevice) async { await keypress("Home", on: device) }

    private func mediaAppId(on device: RokuDevice) async throws -> String? {
        let data = try await ecpGet(device: device, path: "query/apps")
        guard let xml = String(data: data, encoding: .utf8) else { return nil }
        let pattern = #"<app[^>]*id="(\d+)"[^>]*>([^<]+)</app>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        for match in regex.matches(in: xml, options: [], range: ns) {
            guard let idR = Range(match.range(at: 1), in: xml),
                  let nameR = Range(match.range(at: 2), in: xml) else { continue }
            let id = String(xml[idR])
            let name = String(xml[nameR]).lowercased()
            if name.contains("playonroku") || name.contains("play on roku") || name.contains("media player") {
                return id
            }
        }
        return nil
    }

    private func ecpPost(device: RokuDevice, path: String, query: [String: String]) async throws {
        guard let base = URL(string: path, relativeTo: device.baseURL)?.absoluteURL else {
            throw RokuError.playFailed("Bad ECP URL")
        }
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            comps?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps?.url else { throw RokuError.playFailed("Bad ECP URL") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = Data()
        req.timeoutInterval = 8
        let (_, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if !(200...299).contains(code) {
            throw RokuError.playFailed("Roku HTTP \(code) for \(path)")
        }
    }

    private func ecpGet(device: RokuDevice, path: String) async throws -> Data {
        guard let url = URL(string: path, relativeTo: device.baseURL)?.absoluteURL else {
            throw RokuError.playFailed("Bad ECP URL")
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if !(200...299).contains(code) {
            throw RokuError.playFailed("Roku HTTP \(code)")
        }
        return data
    }

    private static func probe(host: String) async -> RokuDevice? {
        guard let url = URL(string: "http://\(host):8060/query/device-info") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 0.7
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            guard let xml = String(data: data, encoding: .utf8) else { return nil }
            let name = tag(xml, "user-device-name")
                ?? tag(xml, "friendly-device-name")
                ?? "Roku"
            let model = tag(xml, "model-name") ?? "Roku"
            let serial = tag(xml, "serial-number") ?? host
            guard let base = URL(string: "http://\(host):8060/") else { return nil }
            return RokuDevice(id: serial, name: name, model: model, baseURL: base)
        } catch {
            return nil
        }
    }

    private static func tag(_ xml: String, _ name: String) -> String? {
        guard let start = xml.range(of: "<\(name)>"),
              let end = xml.range(of: "</\(name)>"),
              start.upperBound < end.lowerBound else { return nil }
        let value = xml[start.upperBound..<end.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func videoFormat(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m3u8": return "hls"
        case "mpd": return "dash"
        case "mkv": return "mkv"
        case "mp4", "m4v": return "mp4"
        default: return "mp4"
        }
    }

    private func localSubnetHosts() -> [String] {
        var hosts: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return hosts }
        defer { freeifaddrs(first) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let flags = Int32(current.pointee.ifa_flags)
            let up = (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING)
            let loopback = (flags & IFF_LOOPBACK) != 0
            if up, !loopback, let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                let ip = String(cString: hostname)
                let parts = ip.split(separator: ".")
                if parts.count == 4, parts[0] != "127" {
                    let prefix = parts.dropLast().joined(separator: ".")
                    let selfOctet = Int(parts[3]) ?? -1
                    for i in 1...254 where i != selfOctet {
                        hosts.append("\(prefix).\(i)")
                    }
                    break
                }
            }
            ptr = current.pointee.ifa_next
        }
        return hosts
    }
}

enum RokuError: LocalizedError {
    case playFailed(String)
    var errorDescription: String? {
        switch self {
        case .playFailed(let s): return s
        }
    }
}
