import Foundation
import os.log

enum NetworkRetry {
  /// Redacts Telegram bot-token pattern `/botNNNN:XXXX/` from strings headed to logs/ActivityLog.
  /// Token appears in URL paths inside URLError.localizedDescription.
  static func redact(_ s: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: "bot\\d+:[A-Za-z0-9_\\-]+", options: []) else {
      return s
    }
    let range = NSRange(s.startIndex..., in: s)
    return regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "bot***:***")
  }

  static func send(
    request: URLRequest,
    session: URLSession = .shared,
    retries: Int = 3,
    delay: TimeInterval = 2.0,
    logger: Logger,
    logCategory: LogCategory,
    completion: (@Sendable (Bool) -> Void)? = nil
  ) {
    session.dataTask(with: request) { _, response, error in
      if let error = error {
        let msg = redact(error.localizedDescription)
        logger.error("Send failed: \(msg)")
        ActivityLog.logAsync(logCategory, "Send failed: \(msg)")
        if retries > 0 {
          logger.info("Retrying... (\(retries) attempts left)")
          DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            send(request: request, session: session, retries: retries - 1,
                 delay: delay, logger: logger, logCategory: logCategory, completion: completion)
          }
          return
        }
        completion?(false)
        return
      } else if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
        let status = httpResponse.statusCode
        logger.error("HTTP error: \(status)")
        ActivityLog.logAsync(logCategory, "HTTP error: \(status)")
        if retries > 0 {
          // Honor Retry-After header on 429; clamp to 60s to avoid stuck retries.
          var waitFor = delay
          if status == 429, let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After"),
             let secs = TimeInterval(retryAfter.trimmingCharacters(in: .whitespaces)) {
            waitFor = min(max(secs, delay), 60)
          }
          logger.info("Retrying in \(waitFor)s... (\(retries) attempts left)")
          DispatchQueue.global().asyncAfter(deadline: .now() + waitFor) {
            send(request: request, session: session, retries: retries - 1,
                 delay: delay, logger: logger, logCategory: logCategory, completion: completion)
          }
          return
        }
        completion?(false)
        return
      }
      logger.debug("Sent")
      ActivityLog.logAsync(logCategory, "Sent")
      completion?(true)
    }.resume()
  }
}
