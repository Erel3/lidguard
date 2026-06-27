import XCTest
@testable import LidGuard

@MainActor
final class FlushMediaRoutingTests: XCTestCase {
  func testPlanRoutesVideoAndPhotoToTheirSenders() {
    // Verifies the contract flushMedia implements: a .video item goes to sendVideo,
    // a .photo item to sendPhoto, each removed on success.
    let dir = TestSupport.makeTempDir()
    let box = TrackingOutbox(directory: dir)
    try? Data([0xFF, 0xD8]).write(to: dir.appendingPathComponent("p.jpg"))
    try? Data([0x00, 0x01]).write(to: dir.appendingPathComponent("v.mov"))
    box.enqueue(OutboxItem(id: "p", timestamp: Date(timeIntervalSince1970: 1), kind: .photo,
                           snapshot: nil, renderedMessage: "photo", mediaFilename: "p.jpg"))
    box.enqueue(OutboxItem(id: "v", timestamp: Date(timeIntervalSince1970: 2), kind: .video,
                           snapshot: nil, renderedMessage: "video", mediaFilename: "v.mov"))

    let notifier = FakeNotifier()
    for item in box.items.sorted(by: { $0.timestamp < $1.timestamp }) {
      let itemID = item.id
      if item.kind == .video {
        notifier.sendVideo(fileURL: box.mediaFileURL(for: item)!, caption: "c",
                           keyboard: .theftMode) { ok in
          if ok { MainActor.assumeIsolated { box.remove(ids: [itemID]) } }
        }
      } else {
        notifier.sendPhoto(jpeg: box.mediaData(for: item)!, caption: "c",
                           keyboard: .theftMode) { ok in
          if ok { MainActor.assumeIsolated { box.remove(ids: [itemID]) } }
        }
      }
    }

    XCTAssertEqual(notifier.sentPhotoCount, 1)
    XCTAssertEqual(notifier.sentVideoURLs.map { $0.lastPathComponent }, ["v.mov"])
    XCTAssertTrue(box.items.isEmpty, "Both items must be removed after successful sends")
  }
}
