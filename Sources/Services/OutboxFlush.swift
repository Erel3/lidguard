import Foundation

/// Pure decision for one flush pass: what single text message to send (a coalesced
/// summary when there is a backlog, otherwise the single rendered message), which
/// text items it consumes, and which photos to send (newest `photoCap`) vs drop.
enum OutboxFlush {
  struct Plan: Equatable {
    var message: String?
    var textItemIDs: [String]
    var photoItemIDs: [String]
    var photoDropIDs: [String]
  }

  static func plan(items: [OutboxItem], photoCap: Int) -> Plan {
    let textItems = items.filter { $0.kind != .photo && $0.kind != .video }.sorted { $0.timestamp < $1.timestamp }
    let photoItems = items.filter { $0.kind == .photo || $0.kind == .video }.sorted { $0.timestamp < $1.timestamp }

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

    let keep = photoItems.suffix(max(0, photoCap))
    let drop = photoItems.dropLast(keep.count)

    return Plan(
      message: message,
      textItemIDs: consumedTextIDs,
      photoItemIDs: keep.map { $0.id },
      photoDropIDs: drop.map { $0.id }
    )
  }
}
