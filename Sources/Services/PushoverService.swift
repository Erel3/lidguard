import Foundation
import os.log

final class PushoverService {
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func send(message: String, priority: Int = 1) {
    guard Config.Pushover.isConfigured && Config.Pushover.isEnabled,
          let userKey = Config.Pushover.userKey,
          let apiToken = Config.Pushover.apiToken else {
      Logger.pushover.debug("Pushover not configured or disabled, skipping")
      return
    }

    guard let url = URL(string: "https://api.pushover.net/1/messages.json") else { return }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: Any] = [
      "token": apiToken,
      "user": userKey,
      "message": message,
      "priority": priority,
      "sound": "siren"
    ]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    NetworkRetry.send(
      request: request,
      session: session,
      logger: Logger.pushover,
      logCategory: .pushover
    )
  }
}
