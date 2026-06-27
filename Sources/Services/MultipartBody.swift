import Foundation

/// Builds a `multipart/form-data` body for Telegram `sendPhoto`. Pure so it is testable.
enum MultipartBody {
  static func make(boundary: String,
                   fields: [(String, String)],
                   jpeg: Data,
                   fieldName: String,
                   filename: String) -> Data {
    var body = Data()
    func append(_ s: String) { body.append(Data(s.utf8)) }

    for (name, value) in fields {
      append("--\(boundary)\r\n")
      append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
      append("\(value)\r\n")
    }

    append("--\(boundary)\r\n")
    append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n")
    append("Content-Type: image/jpeg\r\n\r\n")
    body.append(jpeg)
    append("\r\n")
    append("--\(boundary)--\r\n")
    return body
  }
}
