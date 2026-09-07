import GoogleCast
import UIKit

/// Initializes the Cast SDK before any SwiftUI view reads `GCKCastContext`.
/// Uses Google's Default Media Receiver only (`kGCKDefaultMediaReceiverApplicationID` / CC1AD845).
final class AppDelegate: NSObject, UIApplicationDelegate, GCKLoggerDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let criteria = GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        options.physicalVolumeButtonsWillControlDeviceVolume = true
        options.disableDiscoveryAutostart = true
        options.startDiscoveryAfterFirstTapOnCastButton = true
        options.suspendSessionsWhenBackgrounded = true
        options.stopReceiverApplicationWhenEndingSession = true
        GCKCastContext.setSharedInstanceWith(options)
        GCKLogger.sharedInstance().delegate = self
        CastService.shared.attach()
        return true
    }

    func logMessage(
        _ message: String,
        at level: GCKLoggerLevel,
        fromFunction function: String,
        location: String
    ) {
        #if DEBUG
        NSLog("Cast %@ — %@: %@", String(describing: level), function, message)
        #endif
    }
}
