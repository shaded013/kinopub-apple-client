import XCTest
@testable import KinoPubBackend

final class EpisodePlaybackQueueTests: XCTestCase {
  func testPreviousAndNextFollowSuppliedOrderAcrossSeasons() {
    let s1e1 = episode(id: 11, number: 1, season: 1)
    let s1e2 = episode(id: 12, number: 2, season: 1)
    let s2e1 = episode(id: 21, number: 1, season: 2)
    let queue = EpisodePlaybackQueue(episodes: [s1e1, s1e2, s2e1])

    XCTAssertNil(queue.previous(before: s1e1))
    XCTAssertEqual(queue.next(after: s1e1), s1e2)
    XCTAssertEqual(queue.previous(before: s2e1), s1e2)
    XCTAssertNil(queue.next(after: s2e1))
  }

  func testEpisodeOutsideQueueHasNoNeighbors() {
    let queue = EpisodePlaybackQueue(episodes: [episode(id: 11, number: 1, season: 1)])
    let other = episode(id: 99, number: 1, season: 9)

    XCTAssertNil(queue.previous(before: other))
    XCTAssertNil(queue.next(after: other))
  }

  private func episode(id: Int, number: Int, season: Int) -> Episode {
    let episode = Episode(id: id,
                          title: "Episode \(number)",
                          thumbnail: "",
                          duration: 1_800,
                          tracks: 1,
                          number: number,
                          ac3: 0,
                          audios: [],
                          watched: 0,
                          watching: EpisodeWatching(status: 0, time: 0),
                          subtitles: [],
                          files: [])
    episode.seasonNumber = season
    return episode
  }
}
