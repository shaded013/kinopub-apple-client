//
//  AppDelegate.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 24.07.2023.
//

import Foundation
import SwiftUI
import KinoPubKit
import KinoPubUI

#if os(iOS)
class AppDelegate: NSObject, UIApplicationDelegate {
  
  // This flag is used to lock orientation on the player view
  static var orientationLock = UIInterfaceOrientationMask.all
  
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    ImageCache.shared.purgeExpired()
    return true
  }
  
  func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
    return AppDelegate.orientationLock
  }

  // Called when the app is relaunched in the background to finish events for a background URLSession.
  // We store the completion handler and invoke it once the session reports it finished its events.
  func application(_ application: UIApplication,
                   handleEventsForBackgroundURLSession identifier: String,
                   completionHandler: @escaping () -> Void) {
    switch identifier {
    case DownloadManager<DownloadMeta>.backgroundSessionIdentifier:
      AppContext.shared.downloadManager.handleBackgroundEvents(completionHandler: completionHandler)
    case HLSAssetDownloadManager.backgroundSessionIdentifier:
      AppContext.shared.hlsDownloadManager.handleBackgroundEvents(completionHandler: completionHandler)
    default:
      // The system expects every wake-up to be acknowledged, even if the session belongs to an
      // older app version or is otherwise unknown.
      completionHandler()
    }
  }
}
#endif

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
  
  var window: NSWindow?
  
  func applicationDidFinishLaunching(_ notification: Notification) {
    ImageCache.shared.purgeExpired()
  }

  /// Single-window app: closing the window (red button / Cmd+W) quits, so the user can always leave —
  /// including from the activation screen.
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
#endif
