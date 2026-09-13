import Combine
import Foundation
import UIKit

/// In-app updates. JS/HTML/config apply immediately. No re-sign, no reinstall.
@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    @Published var checking = false
    @Published var lastError: String?
    @Published var banner: String?

    private var timer: Timer?

    private init() {}

    func start() {
        Task { await refresh() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .ddrcastOTAApplied,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                let notes = OTAUpdateService.shared.appliedNotes ?? "Updated"
                self?.banner = notes
            }
        }
    }

    func refresh() async {
        checking = true
        lastError = nil
        defer { checking = false }
        await OTAUpdateService.shared.refresh()
        lastError = OTAUpdateService.shared.lastError
        if OTAUpdateService.shared.didApplyThisSession, banner == nil {
            banner = OTAUpdateService.shared.appliedNotes ?? "ddrcast updated"
        }
    }

    func dismissBanner() {
        banner = nil
    }
}
