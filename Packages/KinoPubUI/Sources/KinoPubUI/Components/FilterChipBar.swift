//
//  FilterChipBar.swift
//
//
//  A single, reusable horizontal "chip" filter bar so every screen with section-style
//  filtering (History, Watching, Collections, …) shares the same native look.
//

import SwiftUI

public struct FilterChipItem: Identifiable, Hashable {
  public let id: String
  public let title: String

  public init(id: String, title: String) {
    self.id = id
    self.title = title
  }
}

public struct FilterChipBar: View {

  // The dark chip surface and selected fill must render even if a named color is unavailable.
  private static let selectedFill = Color(red: 0.42, green: 0.78, blue: 0.53)
  private static let unselectedFill = Color(white: 0.22)

  private let items: [FilterChipItem]
  @Binding private var selection: String

  public init(items: [FilterChipItem], selection: Binding<String>) {
    self.items = items
    self._selection = selection
  }

  public var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(items) { item in
          chip(item)
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 10)
    }
  }

  private func chip(_ item: FilterChipItem) -> some View {
    let isSelected = item.id == selection
    return Button {
      selection = item.id
    } label: {
      Text(item.title)
        .font(.subheadline.weight(isSelected ? .bold : .medium))
        .foregroundStyle(isSelected ? Color.black : Color.KinoPub.text)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minWidth: 44, minHeight: 44)
        .background {
          Capsule(style: .continuous)
            .fill(isSelected ? Self.selectedFill : Self.unselectedFill)
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
