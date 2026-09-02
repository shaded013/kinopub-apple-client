//
//  EpisodePlaybackQueue.swift
//

import Foundation

/// An ordered series queue used by players that can move between episodes without leaving playback.
/// The caller supplies episodes in display order, which also allows a queue to span season boundaries.
public struct EpisodePlaybackQueue: Hashable {
  public let episodes: [Episode]

  public init(episodes: [Episode]) {
    self.episodes = episodes
  }

  public func previous(before current: Episode) -> Episode? {
    guard let index = index(of: current), index > episodes.startIndex else { return nil }
    return episodes[episodes.index(before: index)]
  }

  public func next(after current: Episode) -> Episode? {
    guard let index = index(of: current) else { return nil }
    let nextIndex = episodes.index(after: index)
    return nextIndex < episodes.endIndex ? episodes[nextIndex] : nil
  }

  private func index(of episode: Episode) -> Int? {
    episodes.firstIndex {
      $0.id == episode.id
        && $0.number == episode.number
        && $0.seasonNumber == episode.seasonNumber
    }
  }
}
