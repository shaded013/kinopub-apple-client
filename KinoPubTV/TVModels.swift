import Foundation
import KinoPubBackend

struct TVPlaybackSource: Hashable, Identifiable {
  let mediaID: Int
  let video: Int?
  let season: Int?
  let title: String
  let subtitle: String?
  let artworkURL: URL?
  let files: [FileInfo]

  var id: String {
    "\(mediaID)-\(season ?? 0)-\(video ?? 0)"
  }

  var streamURL: URL? {
    files
      .sorted { $0.resolution > $1.resolution }
      .lazy
      .compactMap { file in
        [file.url.hls4, file.url.hls, file.url.hls2, file.url.http]
          .first(where: { !$0.isEmpty })
          .flatMap(URL.init(string:))
      }
      .first
  }

  static func movie(_ item: MediaItem) -> TVPlaybackSource? {
    guard let video = item.videos?.first else { return nil }
    return TVPlaybackSource(mediaID: item.id,
                            video: video.number,
                            season: nil,
                            title: item.localizedTitle,
                            subtitle: item.year.description,
                            artworkURL: item.wideArtworkURL,
                            files: video.files)
  }

  static func episode(_ episode: Episode, season: Season, item: MediaItem) -> TVPlaybackSource {
    TVPlaybackSource(mediaID: item.id,
                     video: episode.number,
                     season: season.number,
                     title: item.localizedTitle,
                     subtitle: "S\(season.number) · E\(episode.number) · \(episode.fixedTitle)",
                     artworkURL: URL(string: episode.thumbnail),
                     files: episode.files)
  }
}

extension MediaItem {
  var posterURL: URL? {
    URL(string: posters.big.isEmpty ? posters.medium : posters.big)
  }

  var wideArtworkURL: URL? {
    guard let wide = posters.wide, !wide.isEmpty else { return posterURL }
    return URL(string: wide)
  }

  var genreLine: String {
    genres.compactMap(\.title).prefix(3).joined(separator: " · ")
  }
}
