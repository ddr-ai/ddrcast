import Combine
import Foundation

extension Notification.Name {
    static let ddrcastOTAApplied = Notification.Name("ddrcastOTAApplied")
}

struct OTAManifest: Codable {
    var otaVersion: Int
    var minAppBuild: Int?
    var notes: String?
    var files: [String]
}

struct OTAConfig: Codable {
    var rokuAppIds: [String]?
    var rokuPlayPath: String?
    var notes: String?
}

/// Downloads detector JS, home HTML, and config into Application Support.
/// Applied immediately — no IPA reinstall and no re-signing.
@MainActor
final class OTAUpdateService: ObservableObject {
    static let shared = OTAUpdateService()

    static let manifestURL = URL(string: "https://ddr-ai.github.io/ddrcast/ota/manifest.json")!

    @Published private(set) var appliedVersion: Int
    @Published private(set) var appliedNotes: String?
    @Published private(set) var didApplyThisSession = false
    @Published private(set) var lastError: String?

    private let defaultsKey = "ddrcast.otaVersion"
    private var config = OTAConfig()

    var rokuAppIds: [String] {
        let ids = config.rokuAppIds ?? []
        return ids.isEmpty ? ["15985", "2213"] : ids
    }

    private init() {
        appliedVersion = UserDefaults.standard.integer(forKey: defaultsKey)
        loadConfigFromDisk()
    }

    var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("ota", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func fileURL(_ name: String) -> URL? {
        let url = directory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func fileString(_ name: String) -> String? {
        guard let url = fileURL(name) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func refresh() async {
        lastError = nil
        var req = URLRequest(url: Self.manifestURL)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 15
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                lastError = "OTA HTTP \(http.statusCode)"
                return
            }
            let manifest = try JSONDecoder().decode(OTAManifest.self, from: data)
            let appBuild = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
            if let min = manifest.minAppBuild, appBuild < min {
                lastError = "This app build is older than OTA minAppBuild \(min)."
                return
            }
            if manifest.otaVersion <= appliedVersion, fileURL("video-detector.js") != nil {
                return
            }
            let root = Self.manifestURL.deletingLastPathComponent()
            for name in manifest.files {
                let remote = root.appendingPathComponent(name)
                var fileReq = URLRequest(url: remote)
                fileReq.cachePolicy = .reloadIgnoringLocalCacheData
                fileReq.timeoutInterval = 20
                let (fileData, fileResp) = try await URLSession.shared.data(for: fileReq)
                guard let http = fileResp as? HTTPURLResponse, http.statusCode == 200 else { continue }
                let dest = directory.appendingPathComponent(name)
                try fileData.write(to: dest, options: .atomic)
            }
            appliedVersion = manifest.otaVersion
            appliedNotes = manifest.notes
            didApplyThisSession = true
            UserDefaults.standard.set(manifest.otaVersion, forKey: defaultsKey)
            loadConfigFromDisk()
            NotificationCenter.default.post(name: .ddrcastOTAApplied, object: nil)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func loadConfigFromDisk() {
        if let data = fileString("config.json")?.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(OTAConfig.self, from: data) {
            config = decoded
            return
        }
        if let bundled = Bundle.main.url(forResource: "config", withExtension: "json"),
           let data = try? Data(contentsOf: bundled),
           let decoded = try? JSONDecoder().decode(OTAConfig.self, from: data) {
            config = decoded
        }
    }
}
