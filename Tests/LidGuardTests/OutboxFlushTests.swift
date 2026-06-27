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
               photoFilename: nil)
  }

  private func photoItem(id: String, timestamp: Date = Date()) -> OutboxItem {
    OutboxItem(id: id, timestamp: timestamp, kind: .photo,
               snapshot: nil, renderedMessage: nil,
               photoFilename: "\(id).jpg")
  }

  private func minimalSnap(timestamp: Date = Date()) -> DeviceSnapshot {
    DeviceSnapshot(timestamp: timestamp, latitude: nil, longitude: nil,
                   accuracy: nil, publicIP: nil, wifiName: nil,
                   batteryLevel: nil, isCharging: nil, deviceName: "Mac")
  }

  // MARK: - Single text item

  func testSingleTextItemUsesRenderedMessage() {
    let item = textItem(id: "t1", renderedMessage: "Hello world!")
    let plan = OutboxFlush.plan(items: [item], photoCap: 5)
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
    let plan = OutboxFlush.plan(items: [i1, i2], photoCap: 5)
    XCTAssertNotNil(plan.message)
    XCTAssertTrue(plan.message!.contains("OFFLINE SUMMARY"),
                  "Expected coalesced summary, got: \(plan.message!)")
    XCTAssertEqual(Set(plan.textItemIDs), Set(["t1", "t2"]))
  }

  // MARK: - Photo cap: keep NEWEST photoCap, drop older

  func testPhotoCapsKeepNewest() {
    let p1 = photoItem(id: "p1", timestamp: Date(timeIntervalSince1970: 1))
    let p2 = photoItem(id: "p2", timestamp: Date(timeIntervalSince1970: 2))
    let p3 = photoItem(id: "p3", timestamp: Date(timeIntervalSince1970: 3))
    let plan = OutboxFlush.plan(items: [p1, p2, p3], photoCap: 2)
    // Newest 2 kept: p2, p3; oldest dropped: p1
    XCTAssertEqual(Set(plan.photoItemIDs), Set(["p2", "p3"]))
    XCTAssertEqual(plan.photoDropIDs, ["p1"])
  }

  func testPhotoCap0DropsAll() {
    let p1 = photoItem(id: "p1")
    let plan = OutboxFlush.plan(items: [p1], photoCap: 0)
    XCTAssertEqual(plan.photoItemIDs, [])
    XCTAssertEqual(plan.photoDropIDs, ["p1"])
  }

  // MARK: - Empty input

  func testEmptyItemsProducesNilMessageAndNoIDs() {
    let plan = OutboxFlush.plan(items: [], photoCap: 5)
    XCTAssertNil(plan.message)
    XCTAssertEqual(plan.textItemIDs, [])
    XCTAssertEqual(plan.photoItemIDs, [])
    XCTAssertEqual(plan.photoDropIDs, [])
  }

  // MARK: - Nil / empty renderedMessage → item NOT consumed

  func testNilRenderedMessageNotConsumed() {
    let item = textItem(id: "t1", renderedMessage: nil)
    let plan = OutboxFlush.plan(items: [item], photoCap: 5)
    XCTAssertNil(plan.message)
    XCTAssertEqual(plan.textItemIDs, [], "Nil-message item must not be consumed")
  }

  func testEmptyRenderedMessageNotConsumed() {
    let item = textItem(id: "t1", renderedMessage: "")
    let plan = OutboxFlush.plan(items: [item], photoCap: 5)
    XCTAssertNil(plan.message)
    XCTAssertEqual(plan.textItemIDs, [], "Empty-message item must not be consumed")
  }

  // MARK: - Mixed text + photo

  func testMixedItemsTextAndPhoto() {
    let t0 = Date(timeIntervalSince1970: 0)
    let ti = textItem(id: "text1", renderedMessage: "update", timestamp: t0)
    let pi = photoItem(id: "photo1", timestamp: t0.addingTimeInterval(5))
    let plan = OutboxFlush.plan(items: [ti, pi], photoCap: 1)
    XCTAssertEqual(plan.message, "update")
    XCTAssertEqual(plan.textItemIDs, ["text1"])
    XCTAssertEqual(plan.photoItemIDs, ["photo1"])
    XCTAssertEqual(plan.photoDropIDs, [])
  }
}
