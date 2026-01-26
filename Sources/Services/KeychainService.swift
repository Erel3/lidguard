import Foundation

enum KeychainService {
  private static let configDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/lidguard")
  private static let credentialsFile = configDir.appendingPathComponent("credentials.json")

  private static func ensureConfigDir() {
    try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
  }

  private static func loadCredentials() -> [String: String] {
    guard let data = try? Data(contentsOf: credentialsFile),
          let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
      return [:]
    }
    return dict
  }

  private static func saveCredentials(_ credentials: [String: String]) {
    ensureConfigDir()
    if let data = try? JSONEncoder().encode(credentials) {
      try? data.write(to: credentialsFile, options: .atomic)
    }
  }

  @discardableResult
  static func save(key: String, value: String) -> Bool {
    var credentials = loadCredentials()
    credentials[key] = value
    saveCredentials(credentials)
    return true
  }

  static func load(key: String) -> String? {
    loadCredentials()[key]
  }

  @discardableResult
  static func delete(key: String) -> Bool {
    var credentials = loadCredentials()
    credentials.removeValue(forKey: key)
    saveCredentials(credentials)
    return true
  }

  static func deleteAll() {
    try? FileManager.default.removeItem(at: credentialsFile)
  }
}
