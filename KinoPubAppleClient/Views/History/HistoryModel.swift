//
//  HistoryModel.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 24.06.2026.
//

import Foundation
import KinoPubBackend
import KinoPubUI
import OSLog
import KinoPubLogging
import Combine

@MainActor
class HistoryModel: ObservableObject {

  private var authState: AuthState
  private var errorHandler: ErrorHandler
  private var contentService: VideoContentService
  private var authSubscription: AnyCancellable?
  private var refreshTask: Task<Void, Never>?
  private var pageRequestID: UUID?

  let skeletonItems = MediaItem.skeletonMock()
  @Published private(set) var isLoadingSkeleton = true
  @Published private(set) var historyItems: [HistoryItem] = []
  private var pagination: Pagination?
  @Published public var selectedType: MediaType?
  @Published public var toastMessage: ToastMessage?

  init(itemsService: VideoContentService, authState: AuthState, errorHandler: ErrorHandler) {
    self.contentService = itemsService
    self.authState = authState
    self.errorHandler = errorHandler
    // Load on creation, not via the view's `.task` (unreliable in a compact split view / nested stack).
    Task { await refresh() }
  }

  // MARK: - Derived state (filtering + day grouping)

  /// Media types present in the loaded history, in `MediaType.allCases` order. Used to build the filter pills.
  var availableTypes: [MediaType] {
    let present = Set(historyItems.compactMap { MediaType(rawValue: $0.item.type) })
    return MediaType.allCases.filter { present.contains($0) }
  }

  /// History items after applying the selected type filter, preserving recency order.
  private var filteredHistoryItems: [HistoryItem] {
    guard let selectedType else { return historyItems }
    return historyItems.filter { $0.item.type == selectedType.rawValue }
  }

  /// Filtered history grouped by calendar day, newest day first, recency preserved within a day.
  var groupedSections: [HistorySection] {
    let calendar = Calendar.current
    var order: [Date] = []
    var buckets: [Date: [HistoryItem]] = [:]

    for historyItem in filteredHistoryItems {
      let day = calendar.startOfDay(for: historyItem.viewedAt ?? .distantPast)
      if buckets[day] == nil {
        buckets[day] = []
        order.append(day)
      }
      buckets[day]?.append(historyItem)
    }

    return order
      .sorted(by: >)
      .map { day in
        HistorySection(day: day, items: buckets[day] ?? [])
      }
  }

  @Sendable @MainActor
  func refresh() async {
    guard authState.userState == .authorized else {
      subscribeForAuth()
      return
    }
    if let refreshTask {
      await refreshTask.value
      return
    }

    pageRequestID = nil
    // SwiftUI can cancel its refresh action while the pull gesture is still settling.
    // Keep the request alive in the model so the next page-one response can update the list.
    let task = Task { await fetchFirstPage() }
    refreshTask = task
    await task.value
  }

  private func fetchFirstPage() async {
    if !isLoadingSkeleton, errorHandler.state.showError { errorHandler.reset() }
    defer {
      refreshTask = nil
      if isLoadingSkeleton { isLoadingSkeleton = false }
    }

    do {
      let data = try await contentService.fetchHistory(page: nil)
      try Task.checkCancellation()
      historyItems = data.history
      pagination = data.pagination
      if let selectedType, !availableTypes.contains(selectedType) {
        self.selectedType = nil
      }
    } catch {
      guard !Task.isCancelled, !error.isCancellationError else { return }
      Logger.app.debug("fetch history error: \(error)")
      errorHandler.setError(error)
    }
  }

  func loadMoreContent(after item: HistoryItem) {
    guard authState.userState == .authorized, refreshTask == nil, pageRequestID == nil,
          let pagination, pagination.current < pagination.total,
          filteredHistoryItems.last?.uniqueID == item.uniqueID else { return }

    let requestID = UUID()
    pageRequestID = requestID
    Task {
      defer {
        if pageRequestID == requestID { pageRequestID = nil }
      }
      do {
        let data = try await contentService.fetchHistory(page: pagination.current + 1)
        guard pageRequestID == requestID, !Task.isCancelled else { return }
        var seen = Set(historyItems.map(\.uniqueID))
        historyItems.append(contentsOf: data.history.filter { seen.insert($0.uniqueID).inserted })
        self.pagination = data.pagination
      } catch {
        guard pageRequestID == requestID, !Task.isCancelled, !error.isCancellationError else { return }
        Logger.app.debug("load more history error: \(error)")
        errorHandler.setError(error)
      }
    }
  }

  /// Remove a title from watch history (kinoapi `clear-for-media`), optimistically dropping it from
  /// the list and re-syncing on failure.
  func removeFromHistory(_ historyItem: HistoryItem) {
    let itemId = historyItem.item.id
    historyItems.removeAll { $0.item.id == itemId }
    // Also drop any locally-tracked progress so the title disappears from Continue Watching too.
    AppContext.shared.localProgressStore.clear(id: itemId)
    Task {
      do {
        // `clear-for-item` takes the ITEM id (the whole title). The old `clear-for-media` call passed
        // the item id to an endpoint that expects a media id, so it silently cleared nothing and the
        // entry came back on refresh.
        try await AppContext.shared.actionsService.clearHistory(forItem: itemId)
        toastMessage = .info("Removed from history".localized)
      } catch {
        Logger.app.debug("clear history error: \(error)")
        await refresh()
        errorHandler.setError(error)
      }
    }
  }

  private func subscribeForAuth() {
    guard authSubscription == nil else { return }
    authSubscription = authState.$userState.filter({ $0 == .authorized }).first().sink { [weak self] _ in
      Task { [weak self] in
        self?.authSubscription = nil
        await self?.refresh()
      }
    }
  }

}

/// A single day's worth of history entries, used to render a grouped section.
struct HistorySection: Identifiable {
  let day: Date
  let items: [HistoryItem]

  var id: Date { day }

  /// Localized header: "Today"/"Yesterday" when applicable, otherwise a medium localized date.
  var title: String {
    let calendar = Calendar.current
    if calendar.isDateInToday(day) {
      return "Today".localized
    }
    if calendar.isDateInYesterday(day) {
      return "Yesterday".localized
    }
    return HistorySection.dateFormatter.string(from: day)
  }

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
  }()
}
