//
//  Color+Extension.swift
//
//
//  Created by Kirill Kunst on 22.07.2023.
//

import Foundation
import SwiftUI

extension Color {
  public struct KinoPub {
    public static let accent = Color("accent_color", bundle: .module)
    public static let accentRed = Color("accent_red_color", bundle: .module)
    public static let accentBlue = Color("accent_blue_color", bundle: .module)
    public static let background = Color("background_color", bundle: .module)
    // The app is intentionally dark-only. Named dynamic foreground colors can still resolve their
    // light ("Any") variant inside UIKit-backed SwiftUI controls on iOS 26 (TabView, List and
    // TextField), producing black text/icons on the app's black background. Use stable dark-theme
    // foregrounds so the same readable palette reaches both SwiftUI and UIKit-hosted content.
    public static let text = Color(red: 0.86, green: 0.86, blue: 0.88)
    public static let subtitle = Color(red: 0.58, green: 0.58, blue: 0.62)
    public static let selectionBackground = Color("selection_background_color", bundle: .module)
    public static let skeleton = Color("skeleton_color", bundle: .module)
  }
}
