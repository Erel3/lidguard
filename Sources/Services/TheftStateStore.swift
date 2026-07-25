import Foundation

/// Snapshot of theft-mode state persisted across power-off so the app can resume
/// theft mode on the next launch.
struct TheftStateRecord: Codable, Equatable {
  var state: String      // currently only "theftMode" is persisted
  var trigger: String    // TheftTrigger.description at activation time
  var startedAt: Date

  /// Whether this record is recent enough to resume theft mode from.
  ///
  /// `startedAt` exists to bound exactly this: without the check the record has
  /// no expiry at all, and a long-resolved incident can be resumed weeks later —
  /// siren, STOLEN overlay, "DEVICE POWERED BACK ON" alert and a tracking loop
  /// for something already dealt with.
  ///
  /// A record dated in the future (clock adjusted backwards on wake) is rejected
  /// beyond `clockSkew`, because a negative age would otherwise never expire.
  func isResumable(now: Date, maxAge: TimeInterval, clockSkew: TimeInterval) -> Bool {
    let age = now.timeIntervalSince(startedAt)
    return age <= maxAge && age > -clockSkew
  }
}

/// Atomic JSON persistence for the active theft-mode record. Best-effort: all disk
/// failures are swallowed so the app stays functional.
struct TheftStateStore {
  private let fileURL: URL

  init(directory: URL) {
    self.fileURL = directory.appendingPathComponent("theft-state.json")
  }

  func save(_ record: TheftStateRecord) {
    guard let data = try? JSONEncoder().encode(record) else { return }
    try? data.write(to: fileURL, options: .atomic)
  }

  func load() -> TheftStateRecord? {
    guard let data = try? Data(contentsOf: fileURL) else { return nil }
    return try? JSONDecoder().decode(TheftStateRecord.self, from: data)
  }

  func clear() {
    try? FileManager.default.removeItem(at: fileURL)
  }
}
