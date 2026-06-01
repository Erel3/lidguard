import Foundation

/// A GitHub Releases API entry. Shared by the app updater (`UpdateService`)
/// and the helper auto-installer (`HelperInstaller`).
struct GitHubRelease: Decodable, Sendable {
  let tagName: String
  let body: String?
  let assets: [GitHubReleaseAsset]

  /// Tag with a leading "v" stripped, e.g. "v1.2.3" -> "1.2.3".
  var version: String {
    tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
  }

  enum CodingKeys: String, CodingKey {
    case tagName = "tag_name"
    case body
    case assets
  }
}

struct GitHubReleaseAsset: Decodable, Sendable {
  let name: String
  let browserDownloadURL: String

  enum CodingKeys: String, CodingKey {
    case name
    case browserDownloadURL = "browser_download_url"
  }
}
