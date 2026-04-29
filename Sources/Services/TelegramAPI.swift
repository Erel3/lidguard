import Foundation

enum TelegramAPI {
  /// Build long-polling getUpdates URL. Pass `offset = lastUpdateId + 1` to skip seen updates,
  /// or `offset = -1` to fetch only the most recent update (cold-start seed).
  static func updatesURL(botToken: String, offset: Int?, timeout: Int = 1) -> URL? {
    var urlString = "https://api.telegram.org/bot\(botToken)/getUpdates?timeout=\(timeout)"
    if let offset {
      urlString += "&offset=\(offset)"
    }
    return URL(string: urlString)
  }

  /// Parse Telegram `getUpdates` response. Returns the `result` array if `ok: true`.
  static func parseUpdates(_ data: Data) -> [[String: Any]]? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let ok = json["ok"] as? Bool, ok,
          let results = json["result"] as? [[String: Any]] else { return nil }
    return results
  }

  /// Extract `(chatId, text)` from an update's `message` field. NSNumber handles both
  /// 32-bit and 64-bit chat IDs uniformly (Telegram group IDs can exceed Int32).
  static func extractMessage(from update: [String: Any]) -> (chatId: String, text: String)? {
    guard let message = update["message"] as? [String: Any],
          let chat = message["chat"] as? [String: Any],
          let chatId = (chat["id"] as? NSNumber)?.stringValue,
          let text = message["text"] as? String else { return nil }
    return (chatId, text)
  }
}
