import XCTest
@testable import LidGuard

final class MultipartBodyTests: XCTestCase {
  private let boundary = "TestBoundary1234"
  // Minimal "JPEG" bytes — recognizable sequence we can search for verbatim.
  private let jpegData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0xAA, 0xBB, 0xCC, 0xDD])

  private func makeBody(
    fields: [(String, String)] = [("chat_id", "123456")],
    filename: String = "capture.jpg",
    fieldName: String = "photo"
  ) -> Data {
    MultipartBody.make(boundary: boundary, fields: fields,
                       fileData: jpegData, fieldName: fieldName, filename: filename)
  }

  /// Search for a UTF-8 string as a byte subsequence inside the body Data.
  private func body(_ body: Data, contains string: String) -> Bool {
    guard let search = string.data(using: .utf8) else { return false }
    return body.range(of: search) != nil
  }

  // MARK: - Boundary markers

  func testBoundaryOpenerPresent() {
    let b = makeBody()
    XCTAssertTrue(body(b, contains: "--\(boundary)\r\n"), "Boundary opener missing")
  }

  func testBoundaryCloserPresent() {
    let b = makeBody()
    XCTAssertTrue(body(b, contains: "--\(boundary)--\r\n"), "Boundary closer missing")
  }

  // MARK: - Fields

  func testFieldNameAndValuePresent() {
    let b = makeBody(fields: [("chat_id", "9999999")])
    XCTAssertTrue(body(b, contains: "name=\"chat_id\""), "Field name attribute missing")
    XCTAssertTrue(body(b, contains: "9999999"), "Field value missing")
  }

  func testMultipleFieldsAllPresent() {
    let fields = [("chat_id", "777"), ("caption", "Theft detected")]
    let b = makeBody(fields: fields)
    XCTAssertTrue(body(b, contains: "name=\"chat_id\""))
    XCTAssertTrue(body(b, contains: "777"))
    XCTAssertTrue(body(b, contains: "name=\"caption\""))
    XCTAssertTrue(body(b, contains: "Theft detected"))
  }

  // MARK: - Photo part

  func testFilenamePresent() {
    let b = makeBody(filename: "capture.jpg")
    XCTAssertTrue(body(b, contains: "filename=\"capture.jpg\""), "filename attribute missing")
  }

  func testFieldNameForPhotoPartPresent() {
    let b = makeBody(fieldName: "photo")
    XCTAssertTrue(body(b, contains: "name=\"photo\""), "Photo field name missing")
  }

  func testContentTypeIsImageJpeg() {
    let b = makeBody()
    XCTAssertTrue(body(b, contains: "Content-Type: image/jpeg"), "Content-Type header missing")
  }

  // MARK: - Raw JPEG bytes embedded verbatim

  func testRawJpegBytesEmbeddedIntact() {
    let b = makeBody()
    XCTAssertNotNil(b.range(of: jpegData),
                    "Raw JPEG bytes must appear verbatim in the multipart body")
  }

  // MARK: - Video field

  func testVideoFieldAndFilename() {
    let bytes = Data([0x00, 0x00, 0x00, 0x18])
    let b = MultipartBody.make(boundary: "B", fields: [("chat_id", "1")],
                               fileData: bytes, fieldName: "video", filename: "lidguard.mov",
                               contentType: "video/quicktime")
    XCTAssertTrue(body(b, contains: "name=\"video\""), "Video field name must be 'video'")
    XCTAssertTrue(body(b, contains: "filename=\"lidguard.mov\""), "Filename must be lidguard.mov")
    XCTAssertTrue(body(b, contains: "video/quicktime"), "Content-Type must be video/quicktime")
    XCTAssertNotNil(b.range(of: bytes), "Raw video bytes must appear verbatim")
  }
}
