import Foundation

/// Snapshot of theft-mode state persisted across power-off so the app can resume
/// theft mode on the next launch.
struct TheftStateRecord: Codable, Equatable {
  var state: String      // currently only "theftMode" is persisted
  var trigger: String    // TheftTrigger.description at activation time
  var startedAt: Date
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
