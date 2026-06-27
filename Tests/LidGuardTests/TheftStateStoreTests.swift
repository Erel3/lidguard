import XCTest
@testable import LidGuard

final class TheftStateStoreTests: XCTestCase {
  private var dir: URL!
  private var store: TheftStateStore!

  override func setUp() {
    super.setUp()
    dir = TestSupport.makeTempDir()
    store = TheftStateStore(directory: dir)
  }

  func testSaveAndLoadRoundTrip() {
    let record = TheftStateRecord(
      state: "theftMode",
      trigger: "lid_close",
      startedAt: Date(timeIntervalSince1970: 1_000_000)
    )
    store.save(record)
    XCTAssertEqual(store.load(), record)
  }

  func testClearThenLoadReturnsNil() {
    let record = TheftStateRecord(
      state: "theftMode",
      trigger: "power_disconnect",
      startedAt: Date(timeIntervalSince1970: 2_000_000)
    )
    store.save(record)
    store.clear()
    XCTAssertNil(store.load())
  }

  func testLoadNilWhenFileAbsent() {
    XCTAssertNil(store.load())
  }

  func testLoadNilWhenFileIsCorrupt() throws {
    let fileURL = dir.appendingPathComponent("theft-state.json")
    try "not valid json{{{".write(to: fileURL, atomically: true, encoding: .utf8)
    XCTAssertNil(store.load())
  }

  func testReloadAfterSave() {
    let record = TheftStateRecord(state: "theftMode", trigger: "bluetooth", startedAt: Date(timeIntervalSince1970: 5))
    store.save(record)
    // A new store pointing at the same directory should see the same data
    let store2 = TheftStateStore(directory: dir)
    XCTAssertEqual(store2.load(), record)
  }
}
