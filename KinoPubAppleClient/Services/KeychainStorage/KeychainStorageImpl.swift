//
//  KeychainStorageImpl.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 27.07.2023.
//

import Foundation
import KeychainAccess

final class KeychainStorageImpl: KeychainStorage {

  private lazy var keychain: Keychain = {
    return Keychain(service: "com.kunst.kinopub")
  }()

#if os(macOS)
  // Some previous macOS builds stored credentials in UserDefaults to avoid prompts caused by ad-hoc
  // development signatures. Migrate that value back to Keychain as soon as it is encountered,
  // and remove the preference only after the secure write succeeds.
  private let legacyDefaults = UserDefaults.standard
  private let legacyPrefix = "secureStore."
#endif

  func object<Value>(for key: Key<Value>) -> Value? where Value: Decodable, Value: Encodable {
#if os(macOS)
    let legacyKey = legacyPrefix + key.rawValue
    if let data = legacyDefaults.data(forKey: legacyKey),
       let value = try? JSONDecoder().decode(Value.self, from: data) {
      do {
        try keychain.set(data, key: key.rawValue)
        legacyDefaults.removeObject(forKey: legacyKey)
      } catch {
        // Keep the legacy value so migration can be retried instead of logging the user out.
        print(error)
      }
      return value
    }
#endif
    do {
      guard let data = try keychain.getData(key.rawValue) else { return nil }
      return try JSONDecoder().decode(Value.self, from: data)
    } catch {
      print(error)
      return nil
    }
  }

  func setObject<Value>(_ object: Value?, for key: Key<Value>) where Value: Decodable, Value: Encodable {
    guard let object else {
      do {
        try keychain.remove(key.rawValue)
      } catch {
        print(error)
      }
#if os(macOS)
      legacyDefaults.removeObject(forKey: legacyPrefix + key.rawValue)
#endif
      return
    }

    do {
      let data = try JSONEncoder().encode(object)
      try keychain.set(data, key: key.rawValue)
#if os(macOS)
      legacyDefaults.removeObject(forKey: legacyPrefix + key.rawValue)
#endif
    } catch {
      print(error)
    }
  }

  func clear() {
    do {
      try keychain.removeAll()
    } catch {
      print(error)
    }
#if os(macOS)
    for key in legacyDefaults.dictionaryRepresentation().keys where key.hasPrefix(legacyPrefix) {
      legacyDefaults.removeObject(forKey: key)
    }
#endif
  }
}
