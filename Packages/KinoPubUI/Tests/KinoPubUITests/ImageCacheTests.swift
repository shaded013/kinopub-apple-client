import XCTest
import AppKit
@testable import KinoPubUI

final class ImageCacheTests: XCTestCase {
  func testRefreshReportsWhenOriginImageChanges() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ImageURLProtocolStub.self]
    let session = URLSession(configuration: configuration)
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("KinoPubImageCacheTests-\(UUID().uuidString)", isDirectory: true)
    let cache = ImageCache(ttl: 60, session: session, cacheDirectory: directory)
    defer { cache.clear() }

    let url = try XCTUnwrap(URL(string: "https://images.example.test/episode.jpg"))
    ImageURLProtocolStub.payload = imageData(color: .gray)
    let initial = await cache.image(for: url)
    XCTAssertNotNil(initial)

    let unchangedResult = await cache.refreshImage(for: url)
    let unchanged = try XCTUnwrap(unchangedResult)
    XCTAssertFalse(unchanged.contentChanged)

    ImageURLProtocolStub.payload = imageData(color: .green)
    let changedResult = await cache.refreshImage(for: url)
    let changed = try XCTUnwrap(changedResult)
    XCTAssertTrue(changed.contentChanged)
    XCTAssertNotNil(cache.cachedImage(for: url))
  }

  private func imageData(color: NSColor) -> Data {
    let image = NSImage(size: NSSize(width: 2, height: 2))
    image.lockFocus()
    color.setFill()
    NSRect(x: 0, y: 0, width: 2, height: 2).fill()
    image.unlockFocus()
    return image.tiffRepresentation ?? Data()
  }
}

private final class ImageURLProtocolStub: URLProtocol {
  static var payload = Data()

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let response = HTTPURLResponse(url: request.url!,
                                   statusCode: 200,
                                   httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "image/tiff"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Self.payload)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
