import XCTest
@testable import LidGuard

/// Integration-style contract tests: real TrackingOutbox on disk + FakeNotifier,
/// exercising the flush→drain / flush→retain contract.
@MainActor
final class OutboxFlushBehaviorTests: XCTestCase {
  private var outbox: TrackingOutbox!
  private var notifier: FakeNotifier!

  override func setUp() {
    super.setUp()
    outbox = TrackingOutbox(directory: TestSupport.makeTempDir())
    notifier = FakeNotifier()
  }

  // MARK: - Helpers

  private func makeTextItem(id: String, timestamp: Date = Date()) -> OutboxItem {
    let snap = DeviceSnapshot(
      timestamp: timestamp,
      latitude: nil, longitude: nil, accuracy: nil,
      publicIP: nil, wifiName: nil,
      batteryLevel: nil, isCharging: nil,
      deviceName: "Mac"
    )
    return OutboxItem(id: id, timestamp: timestamp, kind: .trackingUpdate,
                      snapshot: snap, renderedMessage: "update-\(id)",
                      mediaFilename: nil)
  }

  // MARK: - Successful flush drains the queue

  func testFlushTwoItemsSendsOneSummaryAndDrainsQueue() {
    let i1 = makeTextItem(id: "t1", timestamp: Date(timeIntervalSince1970: 1))
    let i2 = makeTextItem(id: "t2", timestamp: Date(timeIntervalSince1970: 2))
    outbox.enqueue(i1)
    outbox.enqueue(i2)

    let plan = OutboxFlush.plan(items: outbox.items, photoCap: 0)
    XCTAssertNotNil(plan.message, "Plan must produce a message for 2 queued items")
    XCTAssertTrue(plan.message!.contains("OFFLINE SUMMARY"),
                  "Two items must produce a coalesced summary, got: \(plan.message!)")

    // Simulate successful send: send via notifier, on success remove consumed IDs.
    notifier.nextResult = true
    notifier.send(message: plan.message!, keyboard: .none, completion: nil)
    // nextResult == true → flush succeeded
    outbox.remove(ids: plan.textItemIDs)

    XCTAssertEqual(notifier.sentMessages.count, 1)
    XCTAssertTrue(notifier.sentMessages[0].contains("OFFLINE SUMMARY"))
    XCTAssertEqual(outbox.count, 0, "Queue must drain after successful flush")
  }

  // MARK: - Failed flush retains the queue

  func testFlushRetainsQueueOnFailure() {
    let i1 = makeTextItem(id: "t1", timestamp: Date(timeIntervalSince1970: 1))
    let i2 = makeTextItem(id: "t2", timestamp: Date(timeIntervalSince1970: 2))
    outbox.enqueue(i1)
    outbox.enqueue(i2)

    let plan = OutboxFlush.plan(items: outbox.items, photoCap: 0)

    // Simulate failed send: notifier returns false → do NOT remove items.
    notifier.nextResult = false
    notifier.send(message: plan.message ?? "", keyboard: .none, completion: nil)
    // nextResult == false → flush failed; items retained
    // (no outbox.remove call)

    XCTAssertEqual(outbox.count, 2, "Queue must be retained after a failed flush")
  }

  // MARK: - Single item sends its rendered message directly

  func testSingleItemSendsRenderedMessage() {
    let item = OutboxItem(
      id: "solo",
      timestamp: Date(timeIntervalSince1970: 1),
      kind: .trackingUpdate,
      snapshot: nil,
      renderedMessage: "📍 Location: 37.5, -122.3",
      mediaFilename: nil
    )
    outbox.enqueue(item)

    let plan = OutboxFlush.plan(items: outbox.items, photoCap: 0)
    XCTAssertEqual(plan.message, "📍 Location: 37.5, -122.3")

    notifier.nextResult = true
    notifier.send(message: plan.message!, keyboard: .none, completion: nil)
    outbox.remove(ids: plan.textItemIDs)

    XCTAssertEqual(notifier.sentMessages.count, 1)
    XCTAssertEqual(notifier.sentMessages[0], "📍 Location: 37.5, -122.3")
    XCTAssertEqual(outbox.count, 0)
  }
}
