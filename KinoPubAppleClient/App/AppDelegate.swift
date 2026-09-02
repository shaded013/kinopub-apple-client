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
    configureDarkControlAppearance()
    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    ImageCache.shared.purgeExpired()
    return true
  }

  /// SwiftUI's `.tint` does not reliably reach UIKit-backed TabView/TextField content on iOS 26.
  /// Configure the actual UIKit controls before SwiftUI creates them so selected tab symbols/titles
  /// and the text insertion caret always contrast with the app's dark chrome.
  private func configureDarkControlAppearance() {
    let selectedColor = UIColor(Color.KinoPub.accent)
    let normalColor = UIColor(Color.KinoPub.text).withAlphaComponent(0.82)

    let tabAppearance = UITabBarAppearance()
    tabAppearance.configureWithDefaultBackground()
    configure(tabAppearance.stackedLayoutAppearance,
              normalColor: normalColor,
              selectedColor: selectedColor)
    configure(tabAppearance.inlineLayoutAppearance,
              normalColor: normalColor,
              selectedColor: selectedColor)
    configure(tabAppearance.compactInlineLayoutAppearance,
              normalColor: normalColor,
              selectedColor: selectedColor)

    let tabBar = UITabBar.appearance()
    tabBar.standardAppearance = tabAppearance
    tabBar.scrollEdgeAppearance = tabAppearance
    tabBar.tintColor = selectedColor
    tabBar.unselectedItemTintColor = normalColor

    // This is also set on the concrete Search field, but the appearance default protects any
    // system-hosted text field SwiftUI creates before applying its own environment tint.
    UITextField.appearance().tintColor = selectedColor
  }

  private func configure(_ appearance: UITabBarItemAppearance,
                         normalColor: UIColor,
                         selectedColor: UIColor) {
    appearance.normal.iconColor = normalColor
    appearance.normal.titleTextAttributes = [.foregroundColor: normalColor]
    appearance.selected.iconColor = selectedColor
    appearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]
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
