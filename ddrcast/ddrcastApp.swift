import SwiftUI

@main
struct DDRCastApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var cast = CastService.shared
    @StateObject private var updates = UpdateService.shared
    @StateObject private var browser = BrowserModel()

    var body: some Scene {
        WindowGroup {
            BrowserView()
                .environmentObject(cast)
                .environmentObject(updates)
                .environmentObject(browser)
                .preferredColorScheme(.dark)
                .task { updates.start() }
        }
    }
}
