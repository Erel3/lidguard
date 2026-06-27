import Foundation
import XCTest
@testable import LidGuard

/// Shared test helpers for the LidGuard unit suite.
enum TestSupport {
  /// Creates a unique temporary directory for file-based tests.
  static func makeTempDir() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}

/// Records sends and lets a test drive success/failure for `NotificationService`.
@MainActor
final class FakeNotifier: NotificationService {
  private(set) var sentMessages: [String] = []
  private(set) var sentPhotoCount = 0
  private(set) var sentVideoURLs: [URL] = []
  var nextResult = true

  func send(message: String, keyboard: TelegramKeyboard, completion: (@Sendable (Bool) -> Void)?) {
    sentMessages.append(message)
    completion?(nextResult)
  }

  func sendPhoto(jpeg: Data, caption: String, keyboard: TelegramKeyboard,
                 completion: (@Sendable (Bool) -> Void)?) {
    sentPhotoCount += 1
    completion?(nextResult)
  }

  func sendVideo(fileURL: URL, caption: String, keyboard: TelegramKeyboard,
                 completion: (@Sendable (Bool) -> Void)?) {
    sentVideoURLs.append(fileURL)
    completion?(nextResult)
  }
}
