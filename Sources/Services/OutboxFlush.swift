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
    let textItems = items.filter { $0.kind != .photo }.sorted { $0.timestamp < $1.timestamp }
    let photoItems = items.filter { $0.kind == .photo }.sorted { $0.timestamp < $1.timestamp }

    let message: String?
    if textItems.isEmpty {
      message = nil
    } else if textItems.count == 1 {
      message = textItems[0].renderedMessage
    } else {
      message = CoalesceSummary.build(from: textItems.compactMap { $0.snapshot })
    }

    let keep = photoItems.suffix(max(0, photoCap))
    let drop = photoItems.dropLast(keep.count)

    return Plan(
      message: message,
      textItemIDs: textItems.map { $0.id },
      photoItemIDs: keep.map { $0.id },
      photoDropIDs: drop.map { $0.id }
    )
  }
}
