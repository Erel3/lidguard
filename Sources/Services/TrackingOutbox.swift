import Foundation

/// One queued delivery: a rendered text update or a photo (sidecar JPEG on disk).
struct OutboxItem: Codable, Equatable {
  enum Kind: String, Codable {
    case initialUpdate
    case trackingUpdate
    case photo
  }
  var id: String
  var timestamp: Date
  var kind: Kind
  var snapshot: DeviceSnapshot?   // present for text updates; used for coalesced summaries
  var renderedMessage: String?    // present for text updates; used for single (non-coalesced) sends
  var photoFilename: String?      // present for photo items; sidecar under the outbox dir
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

  func photoData(for item: OutboxItem) -> Data? {
    guard let filename = item.photoFilename else { return nil }
    return try? Data(contentsOf: directory.appendingPathComponent(filename))
  }

  func remove(ids: [String]) {
    let set = Set(ids)
    for item in items where set.contains(item.id) { deletePhoto(item) }
    items.removeAll { set.contains($0.id) }
    persist()
  }

  func clear() {
    for item in items { deletePhoto(item) }
    items.removeAll()
    persist()
  }

  // MARK: - Private

  private func trim() {
    guard items.count > maxItems else { return }
    let overflow = items.count - maxItems
    for item in items.prefix(overflow) { deletePhoto(item) }
    items.removeFirst(overflow)
  }

  private func deletePhoto(_ item: OutboxItem) {
    guard let filename = item.photoFilename else { return }
    try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
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
