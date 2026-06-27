import XCTest
@testable import LidGuard

final class OutboxFlushTests: XCTestCase {
  // MARK: - Helpers

  private func textItem(
    id: String,
    renderedMessage: String?,
    snapshot: DeviceSnapshot? = nil,
    timestamp: Date = Date(),
    kind: OutboxItem.Kind = .trackingUpdate
  ) -> OutboxItem {
    OutboxItem(id: id, timestamp: timestamp, kind: kind,
               snapshot: snapshot, renderedMessage: renderedMessage,
               mediaFilename: nil)
  }

  private func photoItem(id: String, timestamp: Date = Date()) -> OutboxItem {
    OutboxItem(id: id, timestamp: timestamp, kind: .photo,
               snapshot: nil, renderedMessage: nil,
               mediaFilename: "\(id).jpg")
  }

  private func minimalSnap(timestamp: Date = Date()) -> DeviceSnapshot {
    DeviceSnapshot(timestamp: timestamp, latitude: nil, longitude: nil,
                   accuracy: nil, publicIP: nil, wifiName: nil,
                   batteryLevel: nil, isCharging: nil, deviceName: "Mac")
  }

  // MARK: - Single text item

  func testSingleTextItemUsesRenderedMessage() {
    let item = textItem(id: "t1", renderedMessage: "Hello world!")
    let plan = OutboxFlush.plan(items: [item])
    XCTAssertEqual(plan.message, "Hello world!")
    XCTAssertEqual(plan.textItemIDs, ["t1"])
  }

  // MARK: - Multiple text items → coalesced

  func testMultipleTextItemsProduceCoalescedSummary() {
    let t0 = Date(timeIntervalSince1970: 0)
    let i1 = textItem(id: "t1", renderedMessage: "msg1",
                      snapshot: minimalSnap(timestamp: t0), timestamp: t0)
    let i2 = textItem(id: "t2", renderedMessage: "msg2",
                      snapshot: minimalSnap(timestamp: t0.addingTimeInterval(10)),
                      timestamp: t0.addingTimeInterval(10))
    let plan = OutboxFlush.plan(items: [i1, i2])
    XCTAssertNotNil(plan.message)
    XCTAssertTrue(plan.message!.contains("OFFLINE SUMMARY"),
                  "Expected coalesced summary, got: \(plan.message!)")
    XCTAssertEqual(Set(plan.textItemIDs), Set(["t1", "t2"]))
  }

  // MARK: - All media kept (no cap), oldest→newest

  func testAllMediaKeptNoneDropped() {
    let p1 = photoItem(id: "p1", timestamp: Date(timeIntervalSince1970: 1))
    let p2 = photoItem(id: "p2", timestamp: Date(timeIntervalSince1970: 2))
    let p3 = photoItem(id: "p3", timestamp: Date(timeIntervalSince1970: 3))
    let plan = OutboxFlush.plan(items: [p1, p2, p3])
    XCTAssertEqual(plan.mediaItemIDs, ["p1", "p2", "p3"])
  }

  // MARK: - Empty input

  func testEmptyItemsProducesNilMessageAndNoIDs() {
    let plan = OutboxFlush.plan(items: [])
    XCTAssertNil(plan.message)
    XCTAssertEqual(plan.textItemIDs, [])
    XCTAssertEqual(plan.mediaItemIDs, [])
  }

  // MARK: - Nil / empty renderedMessage → item NOT consumed

  func testNilRenderedMessageNotConsumed() {
    let item = textItem(id: "t1", renderedMessage: nil)
    let plan = OutboxFlush.plan(items: [item])
    XCTAssertNil(plan.message)
    XCTAssertEqual(plan.textItemIDs, [], "Nil-message item must not be consumed")
  }

  func testEmptyRenderedMessageNotConsumed() {
    let item = textItem(id: "t1", renderedMessage: "")
    let plan = OutboxFlush.plan(items: [item])
    XCTAssertNil(plan.message)
    XCTAssertEqual(plan.textItemIDs, [], "Empty-message item must not be consumed")
  }

  // MARK: - Mixed text + photo

  func testMixedItemsTextAndPhoto() {
    let t0 = Date(timeIntervalSince1970: 0)
    let ti = textItem(id: "text1", renderedMessage: "update", timestamp: t0)
    let pi = photoItem(id: "photo1", timestamp: t0.addingTimeInterval(5))
    let plan = OutboxFlush.plan(items: [ti, pi])
    XCTAssertEqual(plan.message, "update")
    XCTAssertEqual(plan.textItemIDs, ["text1"])
    XCTAssertEqual(plan.mediaItemIDs, ["photo1"])
  }

  // MARK: - Video treated as media, not text

  func testVideoCountsAsMediaNotText() {
    let video = OutboxItem(id: "v", timestamp: Date(timeIntervalSince1970: 1), kind: .video,
                           snapshot: nil, renderedMessage: "cap", mediaFilename: "v.mov")
    let plan = OutboxFlush.plan(items: [video])
    XCTAssertNil(plan.message)                  // no text to send
    XCTAssertTrue(plan.textItemIDs.isEmpty)
    XCTAssertEqual(plan.mediaItemIDs, ["v"])    // routed as media
  }
}
