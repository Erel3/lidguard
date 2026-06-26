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
/// `sendPhoto` is supplied by the protocol's default extension once it exists; if a
/// test needs to assert photo sends, override it here.
@MainActor
final class FakeNotifier: NotificationService {
  private(set) var sentMessages: [String] = []
  var nextResult = true

  func send(message: String, keyboard: TelegramKeyboard, completion: (@Sendable (Bool) -> Void)?) {
    sentMessages.append(message)
    completion?(nextResult)
  }
}
