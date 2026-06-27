import Foundation

/// Builds a `multipart/form-data` body for Telegram `sendPhoto`. Pure so it is testable.
enum MultipartBody {
  static func make(boundary: String,
                   fields: [(String, String)],
                   fileData: Data,
                   fieldName: String,
                   filename: String,
                   contentType: String = "image/jpeg") -> Data {
    var body = Data()
    func append(_ s: String) { body.append(Data(s.utf8)) }

    for (name, value) in fields {
      append("--\(boundary)\r\n")
      append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
      append("\(value)\r\n")
    }

    append("--\(boundary)\r\n")
    append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n")
    append("Content-Type: \(contentType)\r\n\r\n")
    body.append(fileData)
    append("\r\n")
    append("--\(boundary)--\r\n")
    return body
  }
}
