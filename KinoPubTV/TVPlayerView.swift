import AVKit
import KinoPubBackend
import SwiftUI

struct TVPlayerView: View {
  let source: TVPlaybackSource
  @EnvironmentObject private var session: TVSession

  var body: some View {
    TVPlayerContainer(source: source, session: session)
      .ignoresSafeArea()
  }
}

@MainActor
private struct TVPlayerContainer: View {
  @StateObject private var model: TVPlayerModel

  init(source: TVPlaybackSource, session: TVSession) {
    _model = StateObject(wrappedValue: TVPlayerModel(source: source, session: session))
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      if let player = model.player {
        TVNativePlayer(player: player)
      } else if let error = model.errorMessage {
        VStack(spacing: 22) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 64))
            .foregroundStyle(.orange)
          Text("Playback unavailable")
            .font(.title.weight(.bold))
          Text(error)
            .foregroundStyle(.secondary)
        }
      } else {
        ProgressView()
          .controlSize(.large)
      }
    }
    .task { await model.start() }
    .onDisappear { model.stop() }
  }
}

@MainActor
private final class TVPlayerModel: ObservableObject {
  @Published private(set) var player: AVPlayer?
  @Published private(set) var errorMessage: String?

  private let source: TVPlaybackSource
  private let session: TVSession
  private var timeObserver: Any?
  private var endObserver: NSObjectProtocol?
  private var progressTask: Task<Void, Never>?
  private var didStart = false
  private var didStop = false

  init(source: TVPlaybackSource, session: TVSession) {
    self.source = source
    self.session = session
  }

  func start() async {
    guard !didStart else { return }
    didStart = true

    guard let streamURL = source.streamURL else {
      errorMessage = "No playable HLS source was returned for this title."
      return
    }

    let item = AVPlayerItem(url: streamURL)
    item.externalMetadata = metadata()
    let player = AVPlayer(playerItem: item)
    self.player = player

    if let savedTime = await session.fetchWatchPosition(mediaID: source.mediaID,
                                                        video: source.video,
                                                        season: source.season),
       savedTime > 0 {
      guard !didStop else { return }
      await player.seek(to: CMTime(seconds: savedTime, preferredTimescale: 600))
    }

    guard !didStop else { return }
    installObservers(on: player, item: item)
    player.play()
  }

  func stop() {
    guard !didStop else { return }
    didStop = true
    let current = currentSecond
    player?.pause()
    removeObservers()
    sync(second: current)
  }

  private func installObservers(on player: AVPlayer, item: AVPlayerItem) {
    timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 10, preferredTimescale: 600),
                                                  queue: .main) { [weak self] time in
      guard let self else { return }
      Task { @MainActor in self.sync(second: Int(time.seconds)) }
    }

    endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                         object: item,
                                                         queue: .main) { [weak self] _ in
      guard let self else { return }
      Task { @MainActor in self.sync(second: self.currentSecond) }
    }
  }

  private func removeObservers() {
    if let timeObserver {
      player?.removeTimeObserver(timeObserver)
      self.timeObserver = nil
    }
    if let endObserver {
      NotificationCenter.default.removeObserver(endObserver)
      self.endObserver = nil
    }
  }

  private var currentSecond: Int {
    guard let seconds = player?.currentTime().seconds, seconds.isFinite else { return 0 }
    return max(Int(seconds), 0)
  }

  private func sync(second: Int) {
    let previousTask = progressTask
    let session = session
    let source = source
    progressTask = Task {
      _ = await previousTask?.result
      guard !Task.isCancelled else { return }
      await session.markWatch(mediaID: source.mediaID,
                              time: second,
                              video: source.video,
                              season: source.season)
    }
  }

  private func metadata() -> [AVMetadataItem] {
    let title = AVMutableMetadataItem()
    title.identifier = .commonIdentifierTitle
    title.value = source.title as NSString
    title.extendedLanguageTag = "und"

    var result: [AVMetadataItem] = [title]
    if let subtitle = source.subtitle {
      let description = AVMutableMetadataItem()
      description.identifier = .commonIdentifierDescription
      description.value = subtitle as NSString
      description.extendedLanguageTag = "und"
      result.append(description)
    }
    return result
  }
}

private struct TVNativePlayer: UIViewControllerRepresentable {
  let player: AVPlayer

  func makeUIViewController(context: Context) -> AVPlayerViewController {
    let controller = AVPlayerViewController()
    controller.player = player
    controller.showsPlaybackControls = true
    return controller
  }

  func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
    if controller.player !== player {
      controller.player = player
    }
  }
}
