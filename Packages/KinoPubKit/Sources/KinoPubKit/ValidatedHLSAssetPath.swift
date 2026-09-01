import Foundation

/// Resolves an AVAsset download path only when it remains inside the system-managed HLS directory.
public enum ValidatedHLSAssetPath {
  public static func url(
    for relativePath: String,
    homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
  ) -> URL? {
    guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else { return nil }

    let components = NSString(string: relativePath).pathComponents
    guard components.count >= 3,
          components[0] == "Library",
          components[1] == "com.apple.UserManagedAssets"
            || components[1].hasPrefix("com.apple.UserManagedAssets."),
          !components.contains("..") else { return nil }

    let home = homeDirectory.standardizedFileURL
    let container = home
      .appendingPathComponent(components[0], isDirectory: true)
      .appendingPathComponent(components[1], isDirectory: true)
      .standardizedFileURL
      .resolvingSymlinksInPath()
    let candidate = home
      .appendingPathComponent(relativePath)
      .standardizedFileURL
      .resolvingSymlinksInPath()

    guard container.path.hasPrefix(home.path + "/Library/"),
          candidate.pathExtension.lowercased() == "movpkg",
          candidate.path.hasPrefix(container.path + "/") else { return nil }
    return candidate
  }
}
