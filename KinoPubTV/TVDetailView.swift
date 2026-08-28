import KinoPubBackend
import SwiftUI

@MainActor
private final class TVDetailModel: ObservableObject {
  @Published var item: MediaItem?
  @Published var errorMessage: String?
  @Published var isLoading = false

  func load(id: Int, session: TVSession) async {
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      item = try await session.fetchDetails(id: id)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

struct TVDetailView: View {
  let id: Int
  @EnvironmentObject private var session: TVSession
  @StateObject private var model = TVDetailModel()

  var body: some View {
    ScrollView {
      if let item = model.item {
        detail(item)
      } else if let error = model.errorMessage {
        TVInlineError(message: error) {
          Task { await model.load(id: id, session: session) }
        }
        .padding(.top, 180)
      } else {
        ProgressView()
          .controlSize(.large)
          .frame(maxWidth: .infinity)
          .padding(.top, 220)
      }
    }
    .background(TVTheme.background)
    .ignoresSafeArea(edges: .top)
    .task { await model.load(id: id, session: session) }
    .navigationDestination(for: TVPlaybackSource.self) { source in
      TVPlayerView(source: source)
    }
  }

  @ViewBuilder
  private func detail(_ item: MediaItem) -> some View {
    VStack(alignment: .leading, spacing: 52) {
      detailHero(item)

      if item.isSeries {
        episodeShelves(item)
      }
    }
    .padding(.bottom, 100)
  }

  private func detailHero(_ item: MediaItem) -> some View {
    ZStack(alignment: .bottomLeading) {
      AsyncImage(url: item.wideArtworkURL) { phase in
        if let image = phase.image {
          image.resizable().scaledToFill()
        } else {
          TVTheme.surface
        }
      }
      .frame(height: 690)
      .clipped()

      LinearGradient(colors: [.clear, TVTheme.background.opacity(0.55), TVTheme.background],
                     startPoint: .top,
                     endPoint: .bottom)
      LinearGradient(colors: [TVTheme.background.opacity(0.98), TVTheme.background.opacity(0.1), .clear],
                     startPoint: .leading,
                     endPoint: .trailing)

      HStack(alignment: .bottom, spacing: 52) {
        AsyncImage(url: item.posterURL) { phase in
          if let image = phase.image {
            image.resizable().scaledToFill()
          } else {
            TVTheme.surface
          }
        }
        .frame(width: 260, height: 390)
        .clipped()
        .shadow(color: .black.opacity(0.45), radius: 30, y: 15)

        VStack(alignment: .leading, spacing: 20) {
          Text(item.localizedTitle)
            .font(.system(size: 58, weight: .bold, design: .rounded))
            .lineLimit(2)

          Text([item.year.description, item.genreLine].filter { !$0.isEmpty }.joined(separator: "  ·  "))
            .font(.title3.weight(.medium))
            .foregroundStyle(.secondary)

          Text(item.plot)
            .font(.body)
            .foregroundStyle(.secondary)
            .lineLimit(5)
            .frame(maxWidth: 850, alignment: .leading)

          if let source = primaryPlaybackSource(for: item) {
            NavigationLink(value: source) {
              Label(playLabel(for: item), systemImage: "play.fill")
                .font(.headline.weight(.bold))
            }
            .buttonStyle(.borderedProminent)
            .tint(TVTheme.accent)
            .accessibilityIdentifier("detail.play")
          }
        }
      }
      .padding(.horizontal, 80)
      .padding(.bottom, 35)
    }
    .frame(height: 690)
  }

  @ViewBuilder
  private func episodeShelves(_ item: MediaItem) -> some View {
    let seasons = (item.seasons ?? []).sorted { $0.number < $1.number }
    if seasons.isEmpty {
      Text("Episodes are not available yet.")
        .font(.title2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 80)
    } else {
      ForEach(seasons) { season in
        VStack(alignment: .leading, spacing: 22) {
          Text(season.fixedTitle)
            .font(.title2.weight(.bold))
            .padding(.horizontal, 80)

          ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 34) {
              ForEach(season.episodes.sorted { $0.number < $1.number }) { episode in
                let source = TVPlaybackSource.episode(episode, season: season, item: item)
                NavigationLink(value: source) {
                  TVEpisodeCard(episode: episode)
                }
                .buttonStyle(.card)
                .accessibilityLabel("Season \(season.number), episode \(episode.number), \(episode.fixedTitle)")
              }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 18)
          }
        }
      }
    }
  }

  private func primaryPlaybackSource(for item: MediaItem) -> TVPlaybackSource? {
    if item.isSeries {
      let entry = item.continueEpisode() ?? item.orderedEpisodes.first
      guard let entry else { return nil }
      return .episode(entry.episode, season: entry.season, item: item)
    }
    return .movie(item)
  }

  private func playLabel(for item: MediaItem) -> String {
    if item.isSeries, item.continueEpisode() != nil { return "Continue" }
    if let position = item.videos?.first?.watching.time, position > 0 { return "Continue" }
    return "Play"
  }
}

private struct TVEpisodeCard: View {
  let episode: Episode

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ZStack(alignment: .bottomLeading) {
        AsyncImage(url: URL(string: episode.thumbnail)) { phase in
          if let image = phase.image {
            image.resizable().scaledToFill()
          } else {
            ZStack {
              TVTheme.surface
              Image(systemName: "play.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            }
          }
        }
        .frame(width: 390, height: 220)
        .clipped()

        if episode.watching.time > 0, episode.duration > 0 {
          GeometryReader { geometry in
            Rectangle()
              .fill(TVTheme.accent)
              .frame(width: geometry.size.width * min(Double(episode.watching.time) / Double(episode.duration), 1),
                     height: 7)
              .frame(maxHeight: .infinity, alignment: .bottomLeading)
          }
        }
      }

      Text("E\(episode.number) · \(episode.fixedTitle)")
        .font(.headline)
        .lineLimit(1)
        .frame(width: 390, alignment: .leading)
    }
    .frame(width: 390, alignment: .leading)
  }
}
