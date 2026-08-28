import KinoPubBackend
import SwiftUI

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
private final class TVHomeModel: ObservableObject {
  @Published var continueWatching: [MediaItem] = []
  @Published var freshMovies: [MediaItem] = []
  @Published var popularMovies: [MediaItem] = []
  @Published var freshSeries: [MediaItem] = []
  @Published var featured: MediaItem?
  @Published var errorMessage: String?
  @Published var isLoading = false

  func load(session: TVSession) async {
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }

    do {
      async let history = session.fetchHistory()
      async let freshMovies = session.fetchShelf(shortcut: .fresh, type: .movie)
      async let popularMovies = session.fetchShelf(shortcut: .popular, type: .movie)
      async let freshSeries = session.fetchShelf(shortcut: .fresh, type: .serial)

      let values = try await (history, freshMovies, popularMovies, freshSeries)
      self.continueWatching = Self.unique(values.0.map(\.item))
      self.freshMovies = values.1
      self.popularMovies = values.2
      self.freshSeries = values.3
      featured = continueWatching.first ?? values.1.first ?? values.2.first
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
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
          TVShelf(title: "Fresh movies", items: model.freshMovies, featured: $model.featured)
          TVShelf(title: "Popular now", items: model.popularMovies, featured: $model.featured)
          TVShelf(title: "Fresh series", items: model.freshSeries, featured: $model.featured)

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
      }
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

  var body: some View {
    if !items.isEmpty {
      VStack(alignment: .leading, spacing: 22) {
        Text(title)
          .font(.title2.weight(.bold))
          .padding(.horizontal, 80)

        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(spacing: 34) {
            ForEach(items) { item in
              TVPosterLink(item: item) {
                featured = item
              }
            }
          }
          .padding(.horizontal, 80)
          .padding(.vertical, 18)
        }
      }
    }
  }
}

private struct TVPosterLink: View {
  let item: MediaItem
  let didFocus: () -> Void
  @FocusState private var isFocused: Bool

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
      .frame(width: 230, height: 345)
      .clipped()

      Text(item.localizedTitle)
        .font(.headline)
        .lineLimit(1)
        .frame(width: 230, alignment: .leading)

      Text(item.year.description)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(width: 230, alignment: .leading)
  }
}

@MainActor
private final class TVCatalogModel: ObservableObject {
  @Published var items: [MediaItem] = []
  @Published var errorMessage: String?

  func load(type: MediaType, session: TVSession) async {
    do {
      items = try await session.fetchShelf(shortcut: .fresh, type: type)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 36)], spacing: 50) {
          ForEach(model.items) { item in
            NavigationLink(value: item.id) {
              TVPosterCard(item: item)
            }
            .buttonStyle(.card)
          }
        }
        .padding(80)

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

  func search(session: TVSession) async {
    let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else {
      results = []
      return
    }
    isSearching = true
    defer { isSearching = false }
    do {
      results = try await session.search(value)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
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
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 36)], spacing: 50) {
            ForEach(model.results) { item in
              NavigationLink(value: item.id) {
                TVPosterCard(item: item)
              }
              .buttonStyle(.card)
            }
          }
          .padding(80)
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
