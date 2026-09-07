import Combine
import Foundation
import GoogleCast
import UIKit


enum CastConnectionState: Equatable {
    case idle
    case discovering
    case connecting(String)
    case connected(String)
    case disconnecting
    case failed(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var deviceName: String? {
        switch self {
        case .connecting(let name), .connected(let name): return name
        default: return nil
        }
    }
}

enum CastDeviceName {
    static func display(_ device: GCKDevice) -> String {
        let friendly = device.friendlyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !friendly.isEmpty { return friendly }
        let model = device.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty { return model }
        return "Chromecast"
    }
}

enum TextInputCapability {
    case unsupportedDefaultReceiver
}

@MainActor
final class CastService: NSObject, ObservableObject {
    static let shared = CastService()

    @Published private(set) var connection: CastConnectionState = .idle
    @Published private(set) var devices: [GCKDevice] = []
    @Published private(set) var isDiscovering = false
    @Published private(set) var statusText: String = "Not connected"
    @Published private(set) var nowPlayingTitle: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var lastError: String?
    @Published var volume: Float = 1

    /// Default Media Receiver does not accept remote keyboard text.
    let textInputCapability: TextInputCapability = .unsupportedDefaultReceiver

    private var attached = false
    private var pendingMedia: CastCandidate?
    private weak var loadRequest: GCKRequest?

    private var discovery: GCKDiscoveryManager? {
        guard attached else { return nil }
        return GCKCastContext.sharedInstance().discoveryManager
    }

    private var sessions: GCKSessionManager? {
        guard attached else { return nil }
        return GCKCastContext.sharedInstance().sessionManager
    }

    private var mediaClient: GCKRemoteMediaClient? {
        sessions?.currentCastSession?.remoteMediaClient
    }

    private override init() {
        super.init()
    }

    func attach() {
        guard !attached else { return }
        attached = true
        discovery?.add(self)
        sessions?.add(self)
        refreshDevices()
        if let session = sessions?.currentCastSession {
            let name = CastDeviceName.display(session.device)
            connection = .connected(name)
            statusText = "Connected to \(name)"
            session.remoteMediaClient?.add(self)
        }
    }

    func startDiscovery() {
        guard attached else { return }
        isDiscovering = true
        if case .idle = connection { statusText = "Looking for Chromecast devices…" }
        discovery?.passiveScan = false
        discovery?.startDiscovery()
        refreshDevices()
    }

    func stopDiscovery() {
        discovery?.stopDiscovery()
        isDiscovering = false
        if case .idle = connection { statusText = "Not connected" }
    }

    func connect(to device: GCKDevice) {
        lastError = nil
        let name = CastDeviceName.display(device)
        connection = .connecting(name)
        statusText = "Connecting to \(name)…"
        let ok = sessions?.startSession(with: device) ?? false
        if !ok {
            connection = .failed("Could not start a Cast session with \(name).")
            statusText = "Connection failed"
        }
    }

    func disconnect() {
        lastError = nil
        connection = .disconnecting
        statusText = "Disconnecting…"
        pendingMedia = nil
        nowPlayingTitle = nil
        isPlaying = false
        sessions?.endSessionAndStopCasting(true)
    }

    func cast(_ candidate: CastCandidate) {
        lastError = nil
        guard let session = sessions?.currentCastSession else {
            pendingMedia = candidate
            lastError = "Connect to a Chromecast first, then cast."
            return
        }
        guard let client = session.remoteMediaClient else {
            lastError = "This Cast session has no media channel. Disconnect and try another device."
            return
        }
        let metadata = GCKMediaMetadata(metadataType: .movie)
        metadata.setString(candidate.title, forKey: kGCKMetadataKeyTitle)
        let builder = GCKMediaInformationBuilder(contentURL: candidate.url)
        builder.streamType = .buffered
        builder.contentType = candidate.mime
        builder.metadata = metadata
        let info = builder.build()
        let options = GCKMediaLoadOptions()
        options.autoplay = true
        if candidate.startTime > 1 {
            options.playPosition = candidate.startTime
        }
        client.add(self)
        let request = client.loadMedia(info, with: options)
        request.delegate = self
        loadRequest = request
        nowPlayingTitle = candidate.title
        statusText = "Loading “\(candidate.title)” on \(CastDeviceName.display(session.device))…"
    }

    func togglePlayPause() {
        guard let client = mediaClient else { return }
        if isPlaying {
            client.pause()
        } else {
            client.play()
        }
    }

    func stopMedia() {
        mediaClient?.stop()
        nowPlayingTitle = nil
        isPlaying = false
    }

    func setVolume(_ value: Float) {
        volume = value
        sessions?.currentCastSession?.setDeviceVolume(value)
    }

    func refreshDevices() {
        guard let discovery else {
            devices = []
            return
        }
        var list: [GCKDevice] = []
        let count = Int(discovery.deviceCount)
        if count > 0 {
            for i in 0..<count {
                list.append(discovery.device(at: UInt(i)))
            }
        }
        devices = list
    }
}

extension CastService: GCKDiscoveryManagerListener {
    nonisolated func didUpdateDeviceList() {
        Task { @MainActor in
            self.refreshDevices()
        }
    }

    nonisolated func didStartDiscovery(forDeviceCategory category: String) {
        Task { @MainActor in
            self.isDiscovering = true
        }
    }
}

extension CastService: GCKSessionManagerListener {
    nonisolated func sessionManager(_ sessionManager: GCKSessionManager, willStart session: GCKSession) {
        Task { @MainActor in
            let name = CastDeviceName.display(session.device)
            self.connection = .connecting(name)
            self.statusText = "Connecting to \(name)…"
        }
    }

    nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKCastSession) {
        Task { @MainActor in
            let name = CastDeviceName.display(session.device)
            self.connection = .connected(name)
            self.statusText = "Connected to \(name)"
            self.lastError = nil
            session.remoteMediaClient?.add(self)
            if let pending = self.pendingMedia {
                self.pendingMedia = nil
                self.cast(pending)
            }
        }
    }

    nonisolated func sessionManager(
        _ sessionManager: GCKSessionManager,
        didFailToStart session: GCKSession,
        withError error: Error
    ) {
        Task { @MainActor in
            self.connection = .failed(error.localizedDescription)
            self.statusText = "Connection failed"
            self.lastError = error.localizedDescription
        }
    }

    nonisolated func sessionManager(
        _ sessionManager: GCKSessionManager,
        didEnd session: GCKSession,
        withError error: Error?
    ) {
        Task { @MainActor in
            self.connection = .idle
            self.nowPlayingTitle = nil
            self.isPlaying = false
            if let error {
                self.lastError = error.localizedDescription
                self.statusText = "Disconnected: \(error.localizedDescription)"
            } else {
                self.statusText = "Not connected"
            }
        }
    }
}

extension CastService: GCKRemoteMediaClientListener {
    nonisolated func remoteMediaClient(_ client: GCKRemoteMediaClient, didUpdate mediaStatus: GCKMediaStatus?) {
        Task { @MainActor in
            guard let mediaStatus else {
                self.isPlaying = false
                return
            }
            self.isPlaying = mediaStatus.playerState == .playing
            if let title = mediaStatus.mediaInformation?.metadata?.string(forKey: kGCKMetadataKeyTitle) {
                self.nowPlayingTitle = title
            }
            if let name = self.connection.deviceName {
                let state: String
                switch mediaStatus.playerState {
                case .playing: state = "Playing"
                case .paused: state = "Paused"
                case .buffering, .loading: state = "Buffering"
                case .idle: state = "Idle"
                default: state = "Connected"
                }
                if let title = self.nowPlayingTitle {
                    self.statusText = "\(state) “\(title)” on \(name)"
                } else {
                    self.statusText = "\(state) — \(name)"
                }
            }
        }
    }
}

extension CastService: GCKRequestDelegate {
    nonisolated func requestDidComplete(_ request: GCKRequest) {
        Task { @MainActor in
            if request === self.loadRequest {
                self.lastError = nil
            }
        }
    }

    nonisolated func request(_ request: GCKRequest, didFailWithError error: GCKError) {
        Task { @MainActor in
            guard request === self.loadRequest else { return }
            self.isPlaying = false
            self.lastError = """
            Direct media load failed: \(error.localizedDescription). \
            The Default Media Receiver could not play this URL. \
            ddrcast will not fall back to screen mirroring, and loading the webpage on the receiver is not supported without a custom Cast app.
            """
        }
    }
}
