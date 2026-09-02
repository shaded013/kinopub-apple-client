//
//  DownloadManagerTests.swift
//
//
//  Created by Kirill Kunst on 22.07.2023.
//

import Foundation
import Combine
import XCTest
@testable import KinoPubKit

/// Simple Codable & Equatable metadata used across the KinoPubKit download tests.
struct TestMeta: Codable, Equatable {
  var title: String
}

class DownloadManagerTests: XCTestCase {

  // MARK: - Test Variables

  var downloadManager: DownloadManager<TestMeta>!
  var fileSaverMock: FileSaverMock!
  let metadata = TestMeta(title: "test")

  // MARK: - Test Setup

  override func setUp() {
    super.setUp()

    fileSaverMock = FileSaverMock()
    downloadManager = DownloadManager(fileSaver: fileSaverMock,
                                      database: DownloadedFilesDatabase(fileSaver: fileSaverMock))
  }

  override func tearDown() {
    downloadManager = nil
    fileSaverMock = nil
    super.tearDown()
  }

  // MARK: - Test Methods

  func testStartDownload() {
    // Arrange
    let url = URL(string: "http://example.com/testfile.txt")!

    // Act
    let downloadTaskMock = DownloadTaskMock()
    let download = downloadManager.startDownload(url: url, withMetadata: metadata)
    download.task = downloadTaskMock

    // Assert
    XCTAssertNotNil(download)
    XCTAssertEqual(download.metadata, metadata)
    XCTAssertNotNil(downloadManager.activeDownloads[url])
  }

  func testRemoveDownload() {
    // Arrange
    let url = URL(string: "http://example.com/testfile.txt")!
    let downloadTaskMock = DownloadTaskMock()
    let download = downloadManager.startDownload(url: url, withMetadata: metadata)
    download.task = downloadTaskMock

    // Act
    downloadManager.removeDownload(for: url)

    // Assert
    XCTAssertNil(downloadManager.activeDownloads[url])
  }

  func testCompleteDownload() {
    // Arrange
    let url = URL(string: "http://example.com/testfile.txt")!
    let downloadTaskMock = DownloadTaskMock()
    let download = downloadManager.startDownload(url: url, withMetadata: metadata)
    download.task = downloadTaskMock

    // Act
    downloadManager.completeDownload(url)

    // Assert
    XCTAssertNil(downloadManager.activeDownloads[url])
  }

  func testDidFinishDownloadingTo_Success() {
    // Arrange
    let url = URL(string: "http://example.com/testfile.txt")!
    let locationURL = URL(fileURLWithPath: "/path/to/temporary/location.txt")

    let callbackTask = URLSession.shared.downloadTask(with: URLRequest(url: url))

    // Set the download task on the Download instance.
    let download = downloadManager.startDownload(url: url, withMetadata: metadata)
    download.task = DownloadTaskMock()

    // Act
    downloadManager.urlSession(downloadManager.session,
                               downloadTask: callbackTask,
                               didFinishDownloadingTo: locationURL)

    // Assert
    XCTAssertTrue(fileSaverMock.didSaveFileCalled)
    XCTAssertEqual(fileSaverMock.savedFileSourceURL, locationURL)
    XCTAssertEqual(fileSaverMock.savedFileDestinationURL,
                   fileSaverMock.getDocumentsDirectoryURL(forFilename: "testfile.txt"))
    // The download should be removed from the active list once finished.
    XCTAssertNil(downloadManager.activeDownloads[url])
  }

  func testDidWriteData_UpdatesProgress() {
    // Arrange
    let url = URL(string: "http://example.com/testfile.txt")!
    let callbackTask = URLSession.shared.downloadTask(with: URLRequest(url: url))
    let download = downloadManager.startDownload(url: url, withMetadata: metadata)
    download.task = DownloadTaskMock()

    let expectation = expectation(description: "progress updated")
    let cancellable = download.$progress
      .dropFirst() // skip initial 0.0
      .sink { progress in
        if progress == 0.5 {
          expectation.fulfill()
        }
      }

    // Act
    downloadManager.urlSession(downloadManager.session,
                               downloadTask: callbackTask,
                               didWriteData: 1024,
                               totalBytesWritten: 1024,
                               totalBytesExpectedToWrite: 2048)

    // Assert
    wait(for: [expectation], timeout: 1.0)
    XCTAssertEqual(download.progress, 0.5)
    cancellable.cancel()
  }

  func testBackgroundSession_UsesStableIdentifierAndLaunchEvents() {
    XCTAssertEqual(downloadManager.session.configuration.identifier,
                   DownloadManager<TestMeta>.backgroundSessionIdentifier)
    XCTAssertTrue(downloadManager.session.configuration.sessionSendsLaunchEvents)
    XCTAssertFalse(downloadManager.session.configuration.isDiscretionary)
  }

  func testHandleBackgroundEvents_CompletesWhenSessionFinishes() {
    let completion = expectation(description: "background completion handler called")
    var callCount = 0
    downloadManager.handleBackgroundEvents {
      callCount += 1
      completion.fulfill()
    }

    downloadManager.urlSessionDidFinishEvents(forBackgroundURLSession: downloadManager.session)

    wait(for: [completion], timeout: 1.0)
    XCTAssertEqual(callCount, 1)
  }
}

// MARK: - Mock Classes

final class DownloadTaskMock: DownloadTasking {
  private let resumeBlock: () -> Void
  private let resumeData: Data?

  init(resumeData: Data? = nil, resumeBlock: @escaping () -> Void = {}) {
    self.resumeData = resumeData
    self.resumeBlock = resumeBlock
  }

  func resume() {
    resumeBlock()
  }

  func cancel(byProducingResumeData completionHandler: @escaping @Sendable (Data?) -> Void) {
    completionHandler(resumeData)
  }
}
