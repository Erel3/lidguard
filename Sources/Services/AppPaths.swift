import Foundation

/// Resolves the app's on-disk support directory. Centralized so the outbox and
/// theft-state store share one location.
enum AppPaths {
  /// `~/Library/Application Support/LidGuard`, created if missing.
  /// Locked to owner-only (0700) because it holds queued thief media + location
  /// during an active incident; keep other local accounts out.
  static var supportDirectory: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let dir = base.appendingPathComponent("LidGuard", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
    return dir
  }
}
