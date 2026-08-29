import KinoPubBackend
import SwiftUI

private enum TVBrowseLayout {
  static let horizontalInset: CGFloat = 72
  static let posterWidth: CGFloat = 300
  static let posterHeight: CGFloat = 450
  static let posterSpacing: CGFloat = 42
  static let rowSpacing: CGFloat = 58
  static let columns = Array(
    repeating: GridItem(.fixed(posterWidth), spacing: posterSpacing, alignment: .top),
    count: 5)
}

struct TVRootView: View {
  var body: some View {
    TabView {
      TVHomeView()
        .tabItem { Label("Home", systemImage: "house.fill") }

      TVCatalogView(title: "Movies", type: .movie)
        .tabItem { Label("Movies", systemImage: "movieclapper.fill") }

      TVCatalogView(title: "Series", type: .serial)
        .tabItem { Label("Series", systemImage: "tv.fill") }

      TVSearchView()
        .tabItem { Label("Search", systemImage: "magnifyingglass") }

      TVSettingsView()
        .tabItem { Label("Settings", systemImage: "gearshape.fill") }
    }
    .tint(TVTheme.accent)
  }
}

@MainActor
private enum TVHomeShelf: Hashable {
  case freshMovies
  case popularMovies
  case freshSeries

  var request: (shortcut: MediaShortcut, type: MediaType) {
    switch self {
    case .freshMovies:
      return (.fresh, .movie)
    case .popularMovies:
      return (.popular, .movie)
    case .freshSeries:
      return (.fresh, .serial)
    }
  }
}

@MainActor
private final class TVHomeModel: ObservableObject {
  @Published var continueWatching: [MediaItem] = []
  @Published var freshMovies: [MediaItem] = []
  @Published var popularMovies: [MediaItem] = []
  @Published var freshSeries: [MediaItem] = []
  @Published var featured: MediaItem?
  @Published var errorMessage: String?
  @Published var isLoading = false
  private var paginations: [TVHomeShelf: Pagination] = [:]
  private var loadingShelves = Set<TVHomeShelf>()

  func load(session: TVSession) async {
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }

    do {
      async let history = session.fetchHistory()
      async let freshMovies = session.fetchShelfPage(shortcut: .fresh, type: .movie, page: 1)
      async let popularMovies = session.fetchShelfPage(shortcut: .popular, type: .movie, page: 1)
      async let freshSeries = session.fetchShelfPage(shortcut: .fresh, type: .serial, page: 1)

      let values = try await (history, freshMovies, popularMovies, freshSeries)
      self.continueWatching = Self.unique(values.0.map(\.item))
      self.freshMovies = Self.unique(values.1.items)
      self.popularMovies = Self.unique(values.2.items)
      self.freshSeries = Self.unique(values.3.items)
      paginations[.freshMovies] = values.1.pagination
      paginations[.popularMovies] = values.2.pagination
      paginations[.freshSeries] = values.3.pagination
      featured = continueWatching.first ?? values.1.items.first ?? values.2.items.first
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func loadMore(after item: MediaItem, shelf: TVHomeShelf, session: TVSession) async {
    guard shouldLoadMore(after: item, in: shelf), !loadingShelves.contains(shelf),
          let pagination = paginations[shelf], pagination.current < pagination.total else { return }

    loadingShelves.insert(shelf)
    defer { loadingShelves.remove(shelf) }

    do {
      let request = shelf.request
      let data = try await session.fetchShelfPage(
        shortcut: request.shortcut,
        type: request.type,
        page: pagination.current + 1)
      setItems(Self.unique(items(for: shelf) + data.items), for: shelf)
      paginations[shelf] = data.pagination
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func shouldLoadMore(after item: MediaItem, in shelf: TVHomeShelf) -> Bool {
    let items = items(for: shelf)
    guard let index = items.firstIndex(where: { $0.id == item.id }) else { return false }
    return index >= max(items.count - 5, 0)
  }

  private func items(for shelf: TVHomeShelf) -> [MediaItem] {
    switch shelf {
    case .freshMovies: freshMovies
    case .popularMovies: popularMovies
    case .freshSeries: freshSeries
    }
  }

  private func setItems(_ items: [MediaItem], for shelf: TVHomeShelf) {
    switch shelf {
    case .freshMovies: freshMovies = items
    case .popularMovies: popularMovies = items
    case .freshSeries: freshSeries = items
    }
  }

  private static func unique(_ items: [MediaItem]) -> [MediaItem] {
    var seen = Set<Int>()
    return items.filter { seen.insert($0.id).inserted }
  }
}

struct TVHomeView: View {
  @EnvironmentObject private var session: TVSession
  @StateObject private var model = TVHomeModel()

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 46) {
          if let featured = model.featured {
            TVHero(item: featured)
          } else {
            TVHeroPlaceholder()
          }

          if !model.continueWatching.isEmpty {
            TVShelf(title: "Continue watching", items: model.continueWatching, featured: $model.featured)
          }
          TVShelf(title: "Fresh movies", items: model.freshMovies, featured: $model.featured) { item in
            Task { await model.loadMore(after: item, shelf: .freshMovies, session: session) }
          }
          TVShelf(title: "Popular now", items: model.popularMovies, featured: $model.featured) { item in
            Task { await model.loadMore(after: item, shelf: .popularMovies, session: session) }
          }
          TVShelf(title: "Fresh series", items: model.freshSeries, featured: $model.featured) { item in
            Task { await model.loadMore(after: item, shelf: .freshSeries, session: session) }
          }

          if let error = model.errorMessage {
            TVInlineError(message: error) {
              Task { await model.load(session: session) }
            }
          }
        }
        .padding(.bottom, 90)
      }
      .background(TVTheme.background)
      .ignoresSafeArea(edges: .top)
      .navigationDestination(for: Int.self) { id in
        TVDetailView(id: id)
      }
      .task { await model.load(session: session) }
    }
  }
}

private struct TVHero: View {
  let item: MediaItem

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      AsyncImage(url: item.wideArtworkURL) { phase in
        if let image = phase.image {
          image.resizable().scaledToFill()
        } else {
          TVTheme.surface
        }
      }
      .frame(height: 610)
      .clipped()

      LinearGradient(colors: [.clear, TVTheme.background.opacity(0.35), TVTheme.background],
                     startPoint: .top,
                     endPoint: .bottom)

      LinearGradient(colors: [TVTheme.background.opacity(0.95), .clear],
                     startPoint: .leading,
                     endPoint: .trailing)

      VStack(alignment: .leading, spacing: 18) {
        Text(item.localizedTitle)
          .font(.system(size: 58, weight: .bold, design: .rounded))
          .lineLimit(2)
          .frame(maxWidth: 850, alignment: .leading)

        Text([item.year.description, item.genreLine].filter { !$0.isEmpty }.joined(separator: "  ·  "))
          .font(.title3.weight(.medium))
          .foregroundStyle(.secondary)

        Text(item.plot)
          .font(.body)
          .foregroundStyle(.secondary)
          .lineLimit(3)
          .frame(maxWidth: 760, alignment: .leading)

        NavigationLink(value: item.id) {
          Label("View details", systemImage: "info.circle.fill")
            .font(.headline)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(TVTheme.accent)
        .accessibilityLabel("View details for \(item.localizedTitle)")
      }
      .focusSection()
      .padding(.horizontal, 80)
      .padding(.bottom, 45)
    }
    .frame(height: 610)
  }
}

private struct TVHeroPlaceholder: View {
  var body: some View {
    ZStack(alignment: .bottomLeading) {
      LinearGradient(colors: [TVTheme.accent.opacity(0.2), TVTheme.background],
                     startPoint: .topLeading,
                     endPoint: .bottomTrailing)
      VStack(alignment: .leading, spacing: 16) {
        Text("KINOPUB")
          .font(.headline.weight(.black))
          .foregroundStyle(TVTheme.accent)
        Text("Your cinema, at home.")
          .font(.system(size: 58, weight: .bold, design: .rounded))
      }
      .padding(.horizontal, 80)
      .padding(.bottom, 60)
    }
    .frame(height: 560)
  }
}

private struct TVShelf: View {
  let title: String
  let items: [MediaItem]
  @Binding var featured: MediaItem?
  let didFocusItem: (MediaItem) -> Void

  init(title: String,
       items: [MediaItem],
       featured: Binding<MediaItem?>,
       didFocusItem: @escaping (MediaItem) -> Void = { _ in }) {
    self.title = title
    self.items = items
    _featured = featured
    self.didFocusItem = didFocusItem
  }

  var body: some View {
    if !items.isEmpty {
      VStack(alignment: .leading, spacing: 22) {
        Text(title)
          .font(.title.weight(.bold))
          .padding(.horizontal, TVBrowseLayout.horizontalInset)

        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(alignment: .top, spacing: TVBrowseLayout.posterSpacing) {
            ForEach(items) { item in
              TVPosterLink(item: item) {
                featured = item
                didFocusItem(item)
              }
            }
          }
          .padding(.horizontal, TVBrowseLayout.horizontalInset)
          .padding(.vertical, 26)
        }
      }
    }
  }
}

private struct TVPosterLink: View {
  let item: MediaItem
  let didFocus: () -> Void
  @FocusState private var isFocused: Bool

  init(item: MediaItem,
       didFocus: @escaping () -> Void = {}) {
    self.item = item
    self.didFocus = didFocus
  }

  var body: some View {
    NavigationLink(value: item.id) {
      TVPosterCard(item: item)
    }
    .buttonStyle(.card)
    .focused($isFocused)
    .onChange(of: isFocused) { focused in
      if focused { didFocus() }
    }
    .accessibilityLabel("\(item.localizedTitle), \(item.year)")
  }
}

struct TVPosterCard: View {
  let item: MediaItem

  var body: some View {
    VStack(alignment: .leading, spacing: 13) {
      AsyncImage(url: item.posterURL) { phase in
        if let image = phase.image {
          image.resizable().scaledToFill()
        } else {
          ZStack {
            TVTheme.surface
            Image(systemName: "film")
              .font(.system(size: 48))
              .foregroundStyle(.secondary)
          }
        }
      }
      .frame(width: TVBrowseLayout.posterWidth, height: TVBrowseLayout.posterHeight)
      .clipped()

      Text(item.localizedTitle)
        .font(.title3.weight(.semibold))
        .lineLimit(2)
        .frame(width: TVBrowseLayout.posterWidth, height: 68, alignment: .topLeading)

      Text(item.year.description)
        .font(.body)
        .foregroundStyle(.secondary)
    }
    .frame(width: TVBrowseLayout.posterWidth, alignment: .leading)
  }
}

@MainActor
private final class TVCatalogModel: ObservableObject {
  @Published var items: [MediaItem] = []
  @Published var errorMessage: String?
  @Published var isLoading = false
  @Published var isLoadingMore = false
  @Published var pagination: Pagination?

  func load(type: MediaType, session: TVSession) async {
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }

    do {
      let data = try await session.fetchShelfPage(shortcut: .fresh, type: type, page: 1)
      items = Self.unique(data.items)
      pagination = data.pagination
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func loadMore(after item: MediaItem, type: MediaType, session: TVSession) async {
    guard shouldLoadMore(after: item), !isLoading, !isLoadingMore,
          let pagination, pagination.current < pagination.total else { return }

    isLoadingMore = true
    defer { isLoadingMore = false }

    do {
      let data = try await session.fetchShelfPage(
        shortcut: .fresh,
        type: type,
        page: pagination.current + 1)
      items = Self.unique(items + data.items)
      self.pagination = data.pagination
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func shouldLoadMore(after item: MediaItem) -> Bool {
    guard let index = items.firstIndex(where: { $0.id == item.id }) else { return false }
    return index >= max(items.count - 5, 0)
  }

  private static func unique(_ items: [MediaItem]) -> [MediaItem] {
    var seen = Set<Int>()
    return items.filter { seen.insert($0.id).inserted }
  }
}

struct TVCatalogView: View {
  let title: String
  let type: MediaType
  @EnvironmentObject private var session: TVSession
  @StateObject private var model = TVCatalogModel()

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVGrid(columns: TVBrowseLayout.columns, spacing: TVBrowseLayout.rowSpacing) {
          ForEach(model.items) { item in
            TVPosterLink(item: item) {
              Task { await model.loadMore(after: item, type: type, session: session) }
            }
          }
        }
        .padding(.horizontal, TVBrowseLayout.horizontalInset)
        .padding(.vertical, 46)

        if model.isLoading || model.isLoadingMore {
          TVPageProgress(pagination: model.pagination)
        }

        if let error = model.errorMessage {
          TVInlineError(message: error) {
            Task { await model.load(type: type, session: session) }
          }
        }
      }
      .background(TVTheme.background)
      .navigationTitle(title)
      .navigationDestination(for: Int.self) { id in TVDetailView(id: id) }
      .task { await model.load(type: type, session: session) }
    }
  }
}

@MainActor
private final class TVSearchModel: ObservableObject {
  @Published var query = ""
  @Published var results: [MediaItem] = []
  @Published var errorMessage: String?
  @Published var isSearching = false
  @Published var isLoadingMore = false
  @Published var pagination: Pagination?
  private var pagedQuery = ""

  func search(session: TVSession) async {
    let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else {
      results = []
      pagination = nil
      pagedQuery = ""
      return
    }
    isSearching = true
    results = []
    pagination = nil
    pagedQuery = value
    defer { isSearching = false }
    do {
      let data = try await session.searchPage(value, page: 1)
      guard query.trimmingCharacters(in: .whitespacesAndNewlines) == value else { return }
      results = Self.unique(data.items)
      pagination = data.pagination
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func loadMore(after item: MediaItem, session: TVSession) async {
    guard shouldLoadMore(after: item), !isSearching, !isLoadingMore,
          let pagination, pagination.current < pagination.total else { return }

    let value = pagedQuery
    guard !value.isEmpty else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }

    do {
      let data = try await session.searchPage(value, page: pagination.current + 1)
      guard pagedQuery == value else { return }
      results = Self.unique(results + data.items)
      self.pagination = data.pagination
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func shouldLoadMore(after item: MediaItem) -> Bool {
    guard let index = results.firstIndex(where: { $0.id == item.id }) else { return false }
    return index >= max(results.count - 5, 0)
  }

  private static func unique(_ items: [MediaItem]) -> [MediaItem] {
    var seen = Set<Int>()
    return items.filter { seen.insert($0.id).inserted }
  }
}

struct TVSearchView: View {
  @EnvironmentObject private var session: TVSession
  @StateObject private var model = TVSearchModel()

  var body: some View {
    NavigationStack {
      ScrollView {
        if model.results.isEmpty, !model.isSearching {
          VStack(spacing: 18) {
            Image(systemName: "magnifyingglass")
              .font(.system(size: 72))
              .foregroundStyle(TVTheme.accent)
            Text(model.query.isEmpty ? "Search movies and series" : "No matches")
              .font(.title2.weight(.bold))
            Text("Use the search field above to explore the KinoPub catalogue.")
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
          .padding(.top, 180)
        } else {
          LazyVGrid(columns: TVBrowseLayout.columns, spacing: TVBrowseLayout.rowSpacing) {
            ForEach(model.results) { item in
              TVPosterLink(item: item) {
                Task { await model.loadMore(after: item, session: session) }
              }
            }
          }
          .padding(.horizontal, TVBrowseLayout.horizontalInset)
          .padding(.vertical, 46)

          if model.isSearching || model.isLoadingMore {
            TVPageProgress(pagination: model.pagination)
          }
        }

        if let error = model.errorMessage {
          TVInlineError(message: error) {
            Task { await model.search(session: session) }
          }
        }
      }
      .background(TVTheme.background)
      .navigationTitle("Search")
      .searchable(text: $model.query, prompt: "Title, actor, director")
      .onSubmit(of: .search) { Task { await model.search(session: session) } }
      .navigationDestination(for: Int.self) { id in TVDetailView(id: id) }
    }
  }
}

private struct TVPageProgress: View {
  let pagination: Pagination?

  var body: some View {
    HStack(spacing: 18) {
      ProgressView()
      if let pagination, pagination.total > 1 {
        Text("Loading page \(min(pagination.current + 1, pagination.total)) of \(pagination.total)")
      } else {
        Text("Loading more titles")
      }
    }
    .font(.title3.weight(.medium))
    .foregroundStyle(.secondary)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 46)
  }
}

private struct TVSettingsView: View {
  @EnvironmentObject private var session: TVSession

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 28) {
        Label("KinoPub for Apple TV", systemImage: "play.rectangle.fill")
          .font(.largeTitle.weight(.bold))
          .foregroundStyle(TVTheme.accent)

        Text("Playback progress is synced to your KinoPub account every ten seconds and when you leave the player.")
          .font(.title3)
          .foregroundStyle(.secondary)
          .frame(maxWidth: 760, alignment: .leading)

        Button(role: .destructive) {
          session.logout()
        } label: {
          Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
        }
        .accessibilityIdentifier("settings.signOut")
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(100)
      .background(TVTheme.background)
      .navigationTitle("Settings")
    }
  }
}

struct TVInlineError: View {
  let message: String
  let retry: () -> Void

  var body: some View {
    HStack(spacing: 24) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
      Text(message)
        .lineLimit(2)
      Button("Retry", action: retry)
    }
    .font(.headline)
    .padding(.horizontal, 80)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
