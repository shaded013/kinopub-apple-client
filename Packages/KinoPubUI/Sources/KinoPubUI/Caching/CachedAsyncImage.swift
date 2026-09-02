//
//  CachedAsyncImage.swift
//
//
//  A drop-in replacement for SwiftUI's AsyncImage that loads through ImageCache
//  (memory + disk with a 6-month expiry) instead of hitting the network every time.
//

import SwiftUI

public struct CachedAsyncImage<Content: View, Placeholder: View>: View {

  private let url: URL?
  private let maxCacheAge: TimeInterval?
  private let content: (Image) -> Content
  private let placeholder: () -> Placeholder

  @State private var image: Image?
  @State private var loadedURL: URL?

  public init(url: URL?,
              maxCacheAge: TimeInterval? = nil,
              @ViewBuilder content: @escaping (Image) -> Content,
              @ViewBuilder placeholder: @escaping () -> Placeholder) {
    self.url = url
    self.maxCacheAge = maxCacheAge
    self.content = content
    self.placeholder = placeholder
    // Seed synchronously from the memory cache so already-loaded images don't flash a placeholder.
    if let url, let cached = ImageCache.shared.cachedImage(for: url, maxAge: maxCacheAge) {
      _image = State(initialValue: Image(platformImage: cached))
      _loadedURL = State(initialValue: url)
    }
  }

  public var body: some View {
    Group {
      if let image {
        content(image)
      } else {
        placeholder()
      }
    }
    .task(id: url) {
      await load(url)
    }
  }

  @MainActor
  private func load(_ requestedURL: URL?) async {
    guard let requestedURL else {
      image = nil
      loadedURL = nil
      return
    }
    if loadedURL != requestedURL {
      image = nil
      loadedURL = nil
    }
    guard image == nil else { return }
    if let loaded = await ImageCache.shared.image(for: requestedURL, maxAge: maxCacheAge),
       !Task.isCancelled, url == requestedURL {
      image = Image(platformImage: loaded)
      loadedURL = requestedURL
    }
  }
}

extension Image {
  init(platformImage: KinoPlatformImage) {
#if canImport(UIKit)
    self.init(uiImage: platformImage)
#elseif canImport(AppKit)
    self.init(nsImage: platformImage)
#endif
  }
}
