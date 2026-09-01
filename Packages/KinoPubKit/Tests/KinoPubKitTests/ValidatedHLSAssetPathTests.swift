import XCTest
@testable import KinoPubKit

final class ValidatedHLSAssetPathTests: XCTestCase {
  private let home = URL(fileURLWithPath: "/tmp/KinoPubContainer", isDirectory: true)

  func testAcceptsManagedMovpkgPath() {
    let path = "Library/com.apple.UserManagedAssets.downloads/asset.movpkg"

    XCTAssertEqual(
      ValidatedHLSAssetPath.url(for: path, homeDirectory: home)?.path,
      "/tmp/KinoPubContainer/Library/com.apple.UserManagedAssets.downloads/asset.movpkg"
    )
  }

  func testRejectsPathsOutsideManagedAssetDirectory() {
    let paths = [
      "../Library/com.apple.UserManagedAssets.downloads/asset.movpkg",
      "/Library/com.apple.UserManagedAssets.downloads/asset.movpkg",
      "Documents/asset.movpkg",
      "Library/com.apple.UserManagedAssetsEvil/asset.movpkg",
      "Library/com.apple.UserManagedAssets.downloads/../../Preferences/settings.movpkg",
      "Library/com.apple.UserManagedAssets.downloads/asset.mp4",
    ]

    for path in paths {
      XCTAssertNil(ValidatedHLSAssetPath.url(for: path, homeDirectory: home), path)
    }
  }
}
