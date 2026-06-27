import XCTest
@testable import LidGuard

@MainActor
final class TrackingOutboxTests: XCTestCase {
  private var dir: URL!
  private var outbox: TrackingOutbox!

  override func setUp() {
    super.setUp()
    dir = TestSupport.makeTempDir()
    outbox = TrackingOutbox(directory: dir)
  }

  // MARK: - Helpers

  private func makeItem(
    id: String,
    kind: OutboxItem.Kind = .trackingUpdate,
    timestamp: Date = Date()
  ) -> OutboxItem {
    OutboxItem(id: id, timestamp: timestamp, kind: kind,
               snapshot: nil, renderedMessage: "msg-\(id)",
               photoFilename: nil)
  }

  // MARK: - Enqueue + persist

  func testEnqueuePersistsAcrossReload() {
    outbox.enqueue(makeItem(id: "a1"))
    let outbox2 = TrackingOutbox(directory: dir)
    XCTAssertEqual(outbox2.count, 1)
    XCTAssertEqual(outbox2.items.first?.id, "a1")
  }

  // MARK: - Remove

  func testRemoveByIDs() {
    outbox.enqueue(makeItem(id: "a"))
    outbox.enqueue(makeItem(id: "b"))
    outbox.enqueue(makeItem(id: "c"))
    outbox.remove(ids: ["a", "c"])
    XCTAssertEqual(outbox.count, 1)
    XCTAssertEqual(outbox.items.first?.id, "b")
  }

  func testRemoveUnknownIDsIsNoop() {
    outbox.enqueue(makeItem(id: "x"))
    outbox.remove(ids: ["no-such-id"])
    XCTAssertEqual(outbox.count, 1)
  }

  // MARK: - Cap / trim

  func testCapDropsOldestItems() {
    let capped = TrackingOutbox(directory: TestSupport.makeTempDir(), maxItems: 3)
    capped.enqueue(makeItem(id: "old1", timestamp: Date(timeIntervalSince1970: 1)))
    capped.enqueue(makeItem(id: "old2", timestamp: Date(timeIntervalSince1970: 2)))
    capped.enqueue(makeItem(id: "old3", timestamp: Date(timeIntervalSince1970: 3)))
    capped.enqueue(makeItem(id: "new4", timestamp: Date(timeIntervalSince1970: 4)))
    XCTAssertEqual(capped.count, 3)
    XCTAssertFalse(capped.items.contains { $0.id == "old1" }, "Oldest item should be evicted")
    XCTAssertTrue(capped.items.contains { $0.id == "new4" }, "Newest item must survive")
  }

  // MARK: - Photo sidecar round-trip

  func testStorePhotoAndRetrieveRoundTrip() {
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0xAB, 0xCD])
    let id = "photo-1"
    let filename = outbox.storePhoto(jpeg, id: id)
    XCTAssertNotNil(filename)
    var item = makeItem(id: id, kind: .photo)
    item.photoFilename = filename
    XCTAssertEqual(outbox.photoData(for: item), jpeg)
  }

  func testPhotoDataNilForItemWithoutFilename() {
    let item = makeItem(id: "t1", kind: .trackingUpdate)
    XCTAssertNil(outbox.photoData(for: item))
  }

  // MARK: - Clear

  func testClearEmptiesQueueAndDeletesSidecars() throws {
    let id = "photo-clear"
    let jpeg = Data([0xFF, 0xD8])
    let filename = outbox.storePhoto(jpeg, id: id)!
    var item = makeItem(id: id, kind: .photo)
    item.photoFilename = filename
    outbox.enqueue(item)
    outbox.clear()
    XCTAssertEqual(outbox.count, 0)
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: dir.appendingPathComponent(filename).path),
      "Sidecar JPEG should be deleted on clear"
    )
  }

  // MARK: - Orphan-sidecar reconcile

  func testOrphanSidecarIsDeletedOnInit() throws {
    // Write a .jpg into the outbox dir with no matching OutboxItem.
    let strayFilename = "orphan-\(UUID().uuidString).jpg"
    let strayURL = dir.appendingPathComponent(strayFilename)
    try Data([0xFF, 0xD8, 0x00]).write(to: strayURL)
    // Constructing a new TrackingOutbox should reconcile orphans.
    _ = TrackingOutbox(directory: dir)
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: strayURL.path),
      "Orphan sidecar must be deleted during init reconcile"
    )
  }

  func testReferencedSidecarSurvivedReconcile() throws {
    let jpeg = Data([0xFF, 0xD8])
    let id = "keep-me"
    let filename = outbox.storePhoto(jpeg, id: id)!
    var item = makeItem(id: id, kind: .photo)
    item.photoFilename = filename
    outbox.enqueue(item)
    // Reload — reconcile must NOT delete the referenced sidecar.
    _ = TrackingOutbox(directory: dir)
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: dir.appendingPathComponent(filename).path),
      "Referenced sidecar must survive reconcile"
    )
  }
}
