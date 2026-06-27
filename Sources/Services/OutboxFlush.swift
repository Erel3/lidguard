import Foundation

/// Pure decision for one flush pass: the single text message to send (a coalesced
/// summary when there is a backlog, otherwise the single rendered message), which text
/// items it consumes, and ALL queued media items to send. No media is ever dropped —
/// any captured photo/video may be the one that matters; the persistent queue + retry
/// guarantee eventual delivery rather than discarding on a backlog.
enum OutboxFlush {
  struct Plan: Equatable {
    var message: String?
    var textItemIDs: [String]
    var mediaItemIDs: [String]
  }

  static func plan(items: [OutboxItem]) -> Plan {
    let textItems = items.filter { $0.kind != .photo && $0.kind != .video }.sorted { $0.timestamp < $1.timestamp }
    let mediaItems = items.filter { $0.kind == .photo || $0.kind == .video }.sorted { $0.timestamp < $1.timestamp }

    let rawMessage: String?
    if textItems.isEmpty {
      rawMessage = nil
    } else if textItems.count == 1 {
      rawMessage = textItems[0].renderedMessage
    } else {
      rawMessage = CoalesceSummary.build(from: textItems.compactMap { $0.snapshot })
    }
    // Never consume text items we cannot actually send (nil/empty message) — keep them queued.
    let message = (rawMessage?.isEmpty == false) ? rawMessage : nil
    let consumedTextIDs = message == nil ? [] : textItems.map { $0.id }

    return Plan(
      message: message,
      textItemIDs: consumedTextIDs,
      mediaItemIDs: mediaItems.map { $0.id }
    )
  }
}
