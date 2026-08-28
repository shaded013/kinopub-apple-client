import Foundation
import KinoPubBackend
import Security

@MainActor
final class TVSession: ObservableObject {
  enum Phase {
    case restoring
    case signedOut
    case authorizing
    case signedIn
  }

  @Published private(set) var phase: Phase = .restoring
  @Published private(set) var deviceCode = ""
  @Published private(set) var verificationURL = ""
  @Published private(set) var errorMessage: String?

  private let configuration: TVConfiguration?
  private let tokenStore: TVTokenStore
  private let apiClient: APIClient?
  private var activationTask: Task<Void, Never>?
  private var didRestore = false

  init(bundle: Bundle = .main) {
    let tokenStore = TVTokenStore(service: (bundle.bundleIdentifier ?? "com.kino.pub") + ".oauth")
    self.tokenStore = tokenStore

    if let configuration = try? TVConfiguration(bundle: bundle) {
      self.configuration = configuration
      self.apiClient = APIClient(baseUrl: configuration.baseURL,
                                 plugins: [TVBearerPlugin(tokenStore: tokenStore)],
                                 cache: ResponseCache())
    } else {
      self.configuration = nil
      self.apiClient = nil
    }
  }

  deinit {
    activationTask?.cancel()
  }

  func restore() async {
    guard !didRestore else { return }
    didRestore = true

    guard configuration != nil, apiClient != nil else {
      errorMessage = "KinoPub configuration is missing from this build."
      phase = .signedOut
      return
    }

    guard let token = tokenStore.load() else {
      phase = .signedOut
      return
    }

    phase = .signedIn
    await refresh(using: token)
  }

  func beginActivation() {
    activationTask?.cancel()
    deviceCode = ""
    verificationURL = ""
    errorMessage = nil
    phase = .authorizing

    activationTask = Task { [weak self] in
      guard let self else { return }
      await requestAndPollForDeviceCode()
    }
  }

  func retryActivation() {
    beginActivation()
  }

  func logout() {
    activationTask?.cancel()
    tokenStore.clear()
    apiClient?.clearCache()
    deviceCode = ""
    verificationURL = ""
    errorMessage = nil
    phase = .signedOut
  }

  func fetchShelf(shortcut: MediaShortcut, type: MediaType) async throws -> [MediaItem] {
    try await fetchShelfPage(shortcut: shortcut, type: type, page: 1).items
  }

  func fetchShelfPage(shortcut: MediaShortcut,
                      type: MediaType,
                      page: Int) async throws -> PaginatedData<MediaItem> {
    try await perform(
      ShortcutItemsRequest(shortcut: shortcut, contentType: type, page: page),
      as: PaginatedData<MediaItem>.self)
  }

  func fetchHistory() async throws -> [HistoryItem] {
    let response: HistoryData = try await perform(HistoryRequest(page: 1, perpage: 30), as: HistoryData.self)
    return response.history
  }

  func search(_ query: String) async throws -> [MediaItem] {
    try await searchPage(query, page: 1).items
  }

  func searchPage(_ query: String, page: Int) async throws -> PaginatedData<MediaItem> {
    try await perform(
      SearchItemsRequest(contentType: nil, page: page, query: query),
      as: PaginatedData<MediaItem>.self)
  }

  func fetchDetails(id: Int) async throws -> MediaItem {
    let response: SingleItemData<MediaItem> = try await perform(
      ItemDetailsRequest(id: String(id)),
      as: SingleItemData<MediaItem>.self)
    return response.item
  }

  func fetchWatchPosition(mediaID: Int, video: Int?, season: Int?) async -> TimeInterval? {
    do {
      let response: WatchData = try await perform(
        GetWatchingDataRequest(id: mediaID, video: video, season: season),
        as: WatchData.self)
      if let video {
        if let season {
          return response.item.seasons?
            .first(where: { $0.number == season })?
            .episodes.first(where: { $0.number == video })?.time
        }
        return response.item.videos?.first(where: { $0.number == video })?.time
      }
      return response.item.videos?.first?.time
    } catch {
      return nil
    }
  }

  func markWatch(mediaID: Int, time: Int, video: Int?, season: Int?) async {
    do {
      let _: EmptyResponseData = try await perform(
        MarkTimeRequest(id: mediaID, time: time, video: video, season: season),
        as: EmptyResponseData.self)
    } catch {
      // Progress sync is best-effort. The next periodic mark will retry.
    }
  }

  private func requestAndPollForDeviceCode() async {
    guard let configuration, let apiClient else {
      failActivation("KinoPub configuration is missing from this build.")
      return
    }

    do {
      let request = DeviceCodeRequest(grantType: .deviceCode,
                                      clientID: configuration.clientID,
                                      clientSecret: configuration.clientSecret)
      let verification = try await apiClient.performRequest(with: request,
                                                             decodingType: VerificationResponse.self)
      deviceCode = verification.userCode
      verificationURL = verification.verificationUri
      await poll(verification, configuration: configuration, apiClient: apiClient)
    } catch is CancellationError {
      return
    } catch {
      failActivation(error.localizedDescription)
    }
  }

  private func poll(_ verification: VerificationResponse,
                    configuration: TVConfiguration,
                    apiClient: APIClient) async {
    var interval = max(verification.interval, 1)
    let expiresAt = Date().addingTimeInterval(TimeInterval(verification.expiresIn))

    while !Task.isCancelled {
      if Date() >= expiresAt {
        await requestAndPollForDeviceCode()
        return
      }

      do {
        try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
        try Task.checkCancellation()
        let request = DeviceCodeRequest(grantType: .deviceToken,
                                        clientID: configuration.clientID,
                                        clientSecret: configuration.clientSecret,
                                        code: verification.code)
        let token = try await apiClient.performRequest(with: request, decodingType: AccessToken.self)
        tokenStore.save(token)
        errorMessage = nil
        phase = .signedIn
        return
      } catch is CancellationError {
        return
      } catch let error as APIClientError {
        switch error.backendCode {
        case .authorizationPending:
          continue
        case .slowDown:
          interval += 5
          continue
        case .expiredToken:
          await requestAndPollForDeviceCode()
          return
        default:
          if error.isRetryableTransportFailure { continue }
          failActivation(error.localizedDescription)
          return
        }
      } catch {
        failActivation(error.localizedDescription)
        return
      }
    }
  }

  private func refresh(using token: AccessToken) async {
    guard let configuration, let apiClient else { return }
    do {
      let request = RefreshTokenRequest(clientID: configuration.clientID,
                                        clientSecret: configuration.clientSecret,
                                        refreshToken: token.refreshToken)
      let refreshed = try await apiClient.performRequest(with: request, decodingType: AccessToken.self)
      tokenStore.save(refreshed)
    } catch {
      // Retain the existing session during transient outages. An explicit API error remains visible
      // on the requested screen, where the user can retry or sign out.
    }
  }

  private func perform<T: Decodable>(_ endpoint: Endpoint, as type: T.Type) async throws -> T {
    guard let apiClient else { throw TVSessionError.missingConfiguration }
    return try await apiClient.performRequest(with: endpoint, decodingType: type)
  }

  private func failActivation(_ message: String) {
    errorMessage = message
    phase = .signedOut
  }
}

private struct TVConfiguration {
  let clientID: String
  let clientSecret: String
  let baseURL: String

  init(bundle: Bundle) throws {
    guard let clientID = bundle.object(forInfoDictionaryKey: "ClientID") as? String,
          let clientSecret = bundle.object(forInfoDictionaryKey: "ClientSecret") as? String,
          let baseURL = bundle.object(forInfoDictionaryKey: "BaseURL") as? String,
          !clientID.isEmpty, !clientSecret.isEmpty, !baseURL.isEmpty else {
      throw TVSessionError.missingConfiguration
    }
    self.clientID = clientID
    self.clientSecret = clientSecret
    self.baseURL = baseURL
  }
}

private enum TVSessionError: LocalizedError {
  case missingConfiguration

  var errorDescription: String? {
    "KinoPub configuration is missing from this build."
  }
}

private final class TVBearerPlugin: APIClientPlugin {
  private let tokenStore: TVTokenStore

  init(tokenStore: TVTokenStore) {
    self.tokenStore = tokenStore
  }

  func prepare(_ request: URLRequest) -> URLRequest {
    guard let token = tokenStore.load() else { return request }
    var request = request
    request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
    return request
  }

  func willSend(_ request: URLRequest) {}
  func didReceive(_ response: URLResponse, data: Data?) {}
}

private final class TVTokenStore {
  private let service: String
  private let account = "kinopub-access-token"

  init(service: String) {
    self.service = service
  }

  func load() -> AccessToken? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data else { return nil }
    return try? JSONDecoder().decode(AccessToken.self, from: data)
  }

  func save(_ token: AccessToken) {
    guard let data = try? JSONEncoder().encode(token) else { return }
    SecItemDelete(baseQuery as CFDictionary)
    var item = baseQuery
    item[kSecValueData as String] = data
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(item as CFDictionary, nil)
  }

  func clear() {
    SecItemDelete(baseQuery as CFDictionary)
  }

  private var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
  }
}

private extension APIClientError {
  var backendCode: BackendErrorCode? {
    guard case .networkError(let error) = self else { return nil }
    return (error as? BackendError)?.errorCode
  }

  var isRetryableTransportFailure: Bool {
    guard case .networkError(let error) = self, !(error is BackendError) else { return false }
    return error is URLError || (error as NSError).domain == NSURLErrorDomain
  }
}
