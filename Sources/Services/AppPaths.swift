import Foundation

/// Resolves the app's on-disk support directory. Centralized so the outbox and
/// theft-state store share one location.
enum AppPaths {
  /// `~/Library/Application Support/LidGuard`, created if missing.
  static var supportDirectory: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let dir = base.appendingPathComponent("LidGuard", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }
}
