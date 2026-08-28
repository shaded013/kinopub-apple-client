import SwiftUI

@main
struct KinoPubTVApp: App {
  @StateObject private var session = TVSession()

  var body: some Scene {
    WindowGroup {
      Group {
        switch session.phase {
        case .restoring:
          TVLaunchView()
        case .signedOut, .authorizing:
          TVActivationView()
        case .signedIn:
          TVRootView()
        }
      }
      .environmentObject(session)
      .preferredColorScheme(.dark)
      .tint(TVTheme.accent)
      .task { await session.restore() }
    }
  }
}

enum TVTheme {
  static let background = Color(red: 0.025, green: 0.035, blue: 0.03)
  static let surface = Color(red: 0.075, green: 0.09, blue: 0.08)
  static let accent = Color(red: 0.39, green: 0.78, blue: 0.53)
  static let secondaryText = Color.white.opacity(0.68)
}

private struct TVLaunchView: View {
  var body: some View {
    ZStack {
      TVTheme.background.ignoresSafeArea()
      VStack(spacing: 24) {
        Image(systemName: "play.rectangle.fill")
          .font(.system(size: 88, weight: .medium))
          .foregroundStyle(TVTheme.accent)
        ProgressView()
          .controlSize(.large)
          .accessibilityLabel("Restoring KinoPub session")
      }
    }
  }
}
