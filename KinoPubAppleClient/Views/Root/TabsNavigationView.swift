//
//  TabsView.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 11.08.2023.
//

import Foundation
import SwiftUI
import KinoPubUI
import KinoPubBackend
import KinoPubKit
#if os(iOS)
import UIKit
#endif

// MARK: - Embedded sections
//
// The custom "Ещё" tab is a real NavigationStack that PUSHES the chosen section (so swipe-back and a
// single collapsing nav bar work natively). A pushed section must not wrap itself in its own
// NavigationStack — `\.sectionEmbedded` tells it to render bare and rely on the More tab's stack.

private struct SectionEmbeddedKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  /// True when a top-level screen is pushed inside the custom "Ещё" stack (render without an own stack).
  var sectionEmbedded: Bool {
    get { self[SectionEmbeddedKey.self] }
    set { self[SectionEmbeddedKey.self] = newValue }
  }
}

extension View {
  /// Retained for call-site compatibility; the custom More now uses real push navigation, so the
  /// system supplies the back button and this is a no-op.
  func moreBackButton() -> some View { self }
}

struct TabsNavigationView: View {

  @Environment(\.appContext) var appContext
  @EnvironmentObject var navigationState: NavigationState
  @EnvironmentObject var errorHandler: ErrorHandler
  @EnvironmentObject var authState: AuthState
  @EnvironmentObject var networkMonitor: NetworkMonitor

  @State private var selectedTab: NavigationTabs = .main
  /// Section the user was on before going offline, restored automatically on reconnect.
  @State private var sectionBeforeOffline: NavigationTabs?
  @State private var showReconnected = false
#if os(iOS)
  @State private var isKeyboardVisible = false
#endif

  var placement: ToolbarPlacement {
#if os(iOS)
    .tabBar
#elseif os(macOS)
    .windowToolbar
#endif
  }

  var body: some View {
    configuredTabs
    .safeAreaInset(edge: .top, spacing: 0) {
      if let banner = bannerState {
        OfflineBanner(tone: banner.tone, title: banner.title)
          .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .animation(.easeInOut(duration: 0.25), value: networkMonitor.isOnline)
    .animation(.easeInOut(duration: 0.25), value: showReconnected)
    .onChange(of: networkMonitor.isOnline) { online in
      handleConnectivityChange(online: online)
    }
    // Tapping a download notification opens Downloads (inside the "Ещё" tab).
    .onReceive(NotificationCenter.default.publisher(for: .openDownloads)) { _ in
      selectedTab = .more
    }
#if os(iOS)
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
      isKeyboardVisible = true
    }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
      isKeyboardVisible = false
    }
#endif
    .sheet(isPresented: $authState.shouldShowAuthentication, content: {
      AuthView(model: AuthModel(authService: appContext.authService,
                                authState: authState,
                                errorHandler: errorHandler))
    })
    .environmentObject(navigationState)
    .environmentObject(errorHandler)
    .task {
      Task {
        await authState.check()
      }
    }
  }

  private var tabs: some View {
    TabView(selection: $selectedTab) {
      // Поиск · Я смотрю · Главная (center) · История · Ещё
      searchTab
      watchingTab
      mainTab
      historyTab
      moreTab
    }
  }

  @ViewBuilder
  private var configuredTabs: some View {
#if os(iOS)
    // The iOS 26 system Liquid Glass tab bar can erase the selected item's template image and title
    // on a dark-only app, even when both SwiftUI tint and UITabBarAppearance are explicit. Own the
    // five-button presentation so selection never changes the legibility of its content.
    tabs
      .toolbar(.hidden, for: .tabBar)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if !isKeyboardVisible {
          KinoBottomTabBar(selection: $selectedTab)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
      }
      .animation(.easeInOut(duration: 0.2), value: isKeyboardVisible)
#else
    tabs
    .tint(Color.KinoPub.accent)
#endif
  }

  // MARK: - Offline mode

  private var bannerState: (tone: OfflineBanner.Tone, title: String)? {
    if !networkMonitor.isOnline {
      return (.warning, "You're offline — your downloads are available".localized)
    }
    if showReconnected {
      return (.success, "Back online".localized)
    }
    return nil
  }

  private func handleConnectivityChange(online: Bool) {
    if !online {
      // Downloads live inside "Ещё"; jump there (MoreView opens Downloads automatically offline).
      if selectedTab != .more { sectionBeforeOffline = selectedTab }
      selectedTab = .more
    } else {
      showReconnected = true
      if navigationState.downloadsRoutes.isEmpty, let previous = sectionBeforeOffline {
        selectedTab = previous
      }
      sectionBeforeOffline = nil
      Task {
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        showReconnected = false
      }
    }
  }

  /// Network-only sections show a "needs connection" placeholder while offline.
  @ViewBuilder
  private func networkGated<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    if networkMonitor.isOnline {
      content()
    } else {
      OfflineUnavailableView(title: "Needs a connection".localized,
                             message: "This section isn't available offline.".localized,
                             actionTitle: "Go to Downloads".localized) {
        selectedTab = .more
      }
      .background(Color.KinoPub.background)
    }
  }

  // MARK: - Bottom-bar tabs

  var searchTab: some View {
    networkGated {
      SearchView(model: SearchModel(itemsService: appContext.contentService,
                                    authState: authState,
                                    errorHandler: errorHandler))
    }
#if os(iOS)
    .toolbar(.hidden, for: .tabBar)
#endif
    .tag(NavigationTabs.search)
    .tabItem { Label("Search", systemImage: "magnifyingglass") }
    .toolbarBackground(Color.KinoPub.background, for: placement)
  }

  var watchingTab: some View {
    networkGated {
      WatchingView(model: WatchingModel(itemsService: appContext.contentService,
                                        authState: authState,
                                        errorHandler: errorHandler,
                                        tab: .watchlist))
    }
#if os(iOS)
    .toolbar(.hidden, for: .tabBar)
#endif
    .tag(NavigationTabs.watching)
    .tabItem { Label("Watching", systemImage: "play.tv") }
    .toolbarBackground(Color.KinoPub.background, for: placement)
  }

  var mainTab: some View {
    networkGated {
      HomeView(model: HomeModel(itemsService: appContext.contentService,
                                authState: authState,
                                errorHandler: errorHandler))
    }
#if os(iOS)
    .toolbar(.hidden, for: .tabBar)
#endif
    .tag(NavigationTabs.main)
    .tabItem { Label("Home", systemImage: "house") }
    .toolbarBackground(Color.KinoPub.background, for: placement)
  }

  var historyTab: some View {
    networkGated {
      HistoryView(catalog: HistoryModel(itemsService: appContext.contentService,
                                        authState: authState,
                                        errorHandler: errorHandler))
    }
#if os(iOS)
    .toolbar(.hidden, for: .tabBar)
#endif
    .tag(NavigationTabs.history)
    .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
    .toolbarBackground(Color.KinoPub.background, for: placement)
  }

  var moreTab: some View {
    MoreView()
#if os(iOS)
      .toolbar(.hidden, for: .tabBar)
#endif
      .tag(NavigationTabs.more)
      .tabItem { Label("More", systemImage: "ellipsis") }
      .toolbarBackground(Color.KinoPub.background, for: placement)
  }
}

#if os(iOS)
/// App-owned iPhone navigation bar. Keeping the glyph and title in the same SwiftUI hierarchy as
/// the selection background avoids the iOS 26 UITabBar selected-item rendering regression seen on
/// physical devices while retaining a familiar floating, translucent bar.
private struct KinoBottomTabBar: View {
  @Binding var selection: NavigationTabs

  private struct Item: Identifiable {
    let tab: NavigationTabs
    let title: String
    let systemImage: String

    var id: NavigationTabs { tab }
  }

  private let items = [
    Item(tab: .search, title: "Search", systemImage: "magnifyingglass"),
    Item(tab: .watching, title: "Watching", systemImage: "play.tv"),
    Item(tab: .main, title: "Home", systemImage: "house"),
    Item(tab: .history, title: "History", systemImage: "clock.arrow.circlepath"),
    Item(tab: .more, title: "More", systemImage: "ellipsis")
  ]

  var body: some View {
    HStack(spacing: 2) {
      ForEach(items) { item in
        let isSelected = selection == item.tab
        Button {
          withAnimation(.easeOut(duration: 0.16)) {
            selection = item.tab
          }
        } label: {
          VStack(spacing: 3) {
            Image(systemName: item.systemImage)
              .symbolRenderingMode(.monochrome)
              .font(.system(size: 20, weight: .semibold))
            Text(item.title.localized)
              .font(.system(size: 10, weight: .semibold))
              .lineLimit(1)
              .minimumScaleFactor(0.75)
          }
          .foregroundStyle(isSelected ? Color.KinoPub.accent : Color.KinoPub.text)
          .frame(maxWidth: .infinity)
          .frame(height: 52)
          .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
              .fill(isSelected ? Color.white.opacity(0.16) : Color.clear)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title.localized)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
      }
    }
    .padding(5)
    .background(.ultraThinMaterial, in: Capsule())
    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)).allowsHitTesting(false))
    .padding(.horizontal, 18)
    .padding(.vertical, 6)
  }
}
#endif

// MARK: - Custom "Ещё" — mirrors the iPad sidebar, one navigation bar per screen

struct MoreView: View {
  @Environment(\.appContext) private var appContext
  @EnvironmentObject private var navigationState: NavigationState
  @EnvironmentObject private var errorHandler: ErrorHandler
  @EnvironmentObject private var authState: AuthState
  @EnvironmentObject private var networkMonitor: NetworkMonitor
  @ObservedObject private var visibility = SectionVisibilityStore.shared

  /// Real navigation path (type-erased so it can hold both SidebarItem section pushes and Route
  /// detail pushes from inside the embedded sections).
  @State private var path = NavigationPath()

  private var otherRows: [SidebarItem] { [.newEpisodes, .watching, .bookmarks, .downloads] }

  var body: some View {
    NavigationStack(path: $path) {
      List {
        Section("Library".localized) {
          ForEach(SidebarItem.libraryCategories, id: \.self) { type in
            if visibility.isVisible(.category(type)) { categoryRow(type) }
          }
          ForEach(CatalogPreset.visible) { preset in
            if visibility.isVisible(.preset(preset)) { presetRow(preset) }
          }
          if visibility.isVisible(.sport) { sectionRow(.sport) }
          sectionRow(.collections)
        }
        Section("Other".localized) {
          ForEach(otherRows) { item in
            if visibility.isVisible(item) { sectionRow(item) }
          }
        }
        Section { sectionRow(.profile) }
      }
#if os(iOS)
      .listStyle(.insetGrouped)
#endif
      .scrollContentBackground(.hidden)
      .tint(Color.KinoPub.text)
      .kinoScreen("More".localized)
      // Sections push as bare content onto this one stack (swipe-back + single bar). Details pushed
      // from inside them are Route values handled by .routeDestinations().
      .navigationDestination(for: SidebarItem.self) { item in
        sectionView(item).environment(\.sectionEmbedded, true)
      }
      .routeDestinations()
    }
    // Offline: jump straight to Downloads (the only fully-available section).
    .onChange(of: networkMonitor.isOnline) { online in
      if !online { path = NavigationPath([SidebarItem.downloads]) }
    }
    .onAppear {
      if !networkMonitor.isOnline, path.isEmpty { path.append(SidebarItem.downloads) }
    }
    // Tapping a download notification opens Downloads (TabsNavigationView already switched to this tab).
    .onReceive(NotificationCenter.default.publisher(for: .openDownloads)) { _ in
      path = NavigationPath([SidebarItem.downloads])
    }
  }

  /// A library category opens the shared bare filtered-catalog screen (no nested stack).
  private func categoryRow(_ type: MediaType) -> some View {
    let locked = !networkMonitor.isOnline
    return NavigationLink(value: Route.filteredCatalog(MediaItemsFilter(contentType: type, genres: [], countries: [], year: nil, age: nil, sort: nil), type.title.localized)) {
      rowLabel(type.title.localized, systemImage: type.systemImage, locked: locked)
    }
    .disabled(locked)
    .listRowBackground(Color.KinoPub.background)
  }

  /// A preset section (Cartoons / Anime / Stand-up / 3D) opens a filtered catalog with its type+genre.
  private func presetRow(_ preset: CatalogPreset) -> some View {
    let locked = !networkMonitor.isOnline
    return NavigationLink(value: Route.filteredCatalog(preset.filter, preset.title.localized)) {
      rowLabel(preset.title.localized, systemImage: preset.systemImage, locked: locked)
    }
    .disabled(locked)
    .listRowBackground(Color.KinoPub.background)
  }

  private func sectionRow(_ item: SidebarItem) -> some View {
    let locked = !networkMonitor.isOnline && !item.isAvailableOffline
    return NavigationLink(value: item) {
      rowLabel(item.title.localized, systemImage: item.systemImage, locked: locked)
    }
    .disabled(locked)
    .listRowBackground(Color.KinoPub.background)
  }

  private func rowLabel(_ title: String, systemImage: String, locked: Bool) -> some View {
    HStack {
      Label(title, systemImage: systemImage)
      if locked {
        Spacer()
        Image(systemName: "lock.fill").font(.caption2)
      }
    }
    .foregroundStyle(locked ? Color.KinoPub.subtitle : Color.KinoPub.text)
  }

  @ViewBuilder
  private func sectionView(_ item: SidebarItem) -> some View {
    switch item {
    case .sport:
      SportView(model: SportModel(itemsService: appContext.contentService,
                                  epgService: appContext.epgService,
                                  authState: authState,
                                  errorHandler: errorHandler))
    case .collections:
      CollectionsView(model: CollectionsModel(collectionsService: appContext.collectionsService,
                                              authState: authState,
                                              errorHandler: errorHandler))
    case .newEpisodes:
      WatchingView(model: WatchingModel(itemsService: appContext.contentService,
                                        authState: authState,
                                        errorHandler: errorHandler,
                                        tab: .newEpisodes))
    case .watching:
      WatchingView(model: WatchingModel(itemsService: appContext.contentService,
                                        authState: authState,
                                        errorHandler: errorHandler,
                                        tab: .watchlist))
    case .bookmarks:
      BookmarksView(catalog: BookmarksCatalog(itemsService: appContext.contentService,
                                              authState: authState,
                                              errorHandler: errorHandler))
    case .downloads:
      DownloadsView(catalog: DownloadsCatalog(downloadsDatabase: appContext.downloadedFilesDatabase,
                                              downloadManager: appContext.downloadManager))
    case .profile:
      ProfileView(model: ProfileModel(userService: appContext.userService,
                                      errorHandler: errorHandler,
                                      authState: authState))
    default:
      EmptyView()
    }
  }
}

struct TabsNavigationView_Previews: PreviewProvider {
  static var previews: some View {
    TabsNavigationView()
  }
}
