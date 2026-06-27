import Foundation

/// One queued delivery: a rendered text update or a photo (sidecar JPEG on disk).
struct OutboxItem: Codable, Equatable {
  enum Kind: String, Codable {
    case initialUpdate
    case trackingUpdate
    case photo
    case video
  }
  var id: String
  var timestamp: Date
  var kind: Kind
  var snapshot: DeviceSnapshot?   // present for text updates; used for coalesced summaries
  var renderedMessage: String?    // present for text updates; used for single (non-coalesced) sends
  var mediaFilename: String?      // "<id>.jpg" for photo, "<id>.mov" for video
}

/// Disk-backed FIFO of pending Telegram deliveries. Survives relaunch so updates
/// captured just before a power-off are not lost. Best-effort persistence.
@MainActor
final class TrackingOutbox {
  private let directory: URL
  private let indexURL: URL
  private let maxItems: Int
  private(set) var items: [OutboxItem]

  init(directory: URL, maxItems: Int = 500) {
    self.directory = directory
    self.indexURL = directory.appendingPathComponent("outbox.json")
    self.maxItems = maxItems
    self.items = Self.loadIndex(indexURL)
    reconcileOrphanSidecars()
  }

  var count: Int { items.count }

  func enqueue(_ item: OutboxItem) {
    items.append(item)
    trim()
    persist()
  }

  /// Writes JPEG bytes to `<id>.jpg`; returns the filename to store on the item.
  func storePhoto(_ data: Data, id: String) -> String? {
    let filename = "\(id).jpg"
    do {
      try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
      return filename
    } catch {
      return nil
    }
  }

  /// Moves a recorded temp `.mov` into the outbox dir as `<id>.mov`; returns the filename.
  func storeVideo(from tempURL: URL, id: String) -> String? {
    let filename = "\(id).mov"
    let dest = directory.appendingPathComponent(filename)
    do {
      try? FileManager.default.removeItem(at: dest)
      try FileManager.default.moveItem(at: tempURL, to: dest)
      return filename
    } catch {
      try? FileManager.default.removeItem(at: tempURL)   // don't leak the temp recording
      return nil
    }
  }

  func mediaData(for item: OutboxItem) -> Data? {
    guard let filename = item.mediaFilename else { return nil }
    return try? Data(contentsOf: directory.appendingPathComponent(filename))
  }

  func mediaFileURL(for item: OutboxItem) -> URL? {
    guard let filename = item.mediaFilename else { return nil }
    return directory.appendingPathComponent(filename)
  }

  func remove(ids: [String]) {
    let set = Set(ids)
    for item in items where set.contains(item.id) { deleteMedia(item) }
    items.removeAll { set.contains($0.id) }
    persist()
  }

  func clear() {
    for item in items { deleteMedia(item) }
    items.removeAll()
    persist()
  }

  // MARK: - Private

  private func trim() {
    guard items.count > maxItems else { return }
    let overflow = items.count - maxItems
    for item in items.prefix(overflow) { deleteMedia(item) }
    items.removeFirst(overflow)
  }

  private func deleteMedia(_ item: OutboxItem) {
    guard let filename = item.mediaFilename else { return }
    try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
  }

  /// Deletes any `*.jpg`/`*.mov` sidecar with no matching OutboxItem (e.g. a crash between
  /// store and enqueue), so orphaned media doesn't accumulate on disk.
  private func reconcileOrphanSidecars() {
    let referenced = Set(items.compactMap { $0.mediaFilename })
    guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
    for file in files where (file.hasSuffix(".jpg") || file.hasSuffix(".mov")) && !referenced.contains(file) {
      try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
    }
  }

  private func persist() {
    guard let data = try? JSONEncoder().encode(items) else { return }
    try? data.write(to: indexURL, options: .atomic)
  }

  private static func loadIndex(_ url: URL) -> [OutboxItem] {
    guard let data = try? Data(contentsOf: url),
          let items = try? JSONDecoder().decode([OutboxItem].self, from: data) else { return [] }
    return items
  }
}
