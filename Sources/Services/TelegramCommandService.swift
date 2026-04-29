import Foundation
import os.log

@MainActor
protocol TelegramCommandDelegate: AnyObject {
  func telegramCommandReceived(_ command: TelegramCommand)
}

enum TelegramCommand: String {
  case stop = "/stop"
  case safe = "/safe"
  case status = "/status"
  case enable = "/enable"
  case disable = "/disable"
  case alarm = "/alarm"
  case stopalarm = "/stopalarm"
}

@MainActor
final class TelegramCommandService {
  weak var delegate: TelegramCommandDelegate?

  private let session: URLSession

  private var timer: DispatchSourceTimer?
  private var lastUpdateId: Int?
  private let pollInterval: TimeInterval
  private var isPolling = false
  private var seeded = false

  init(session: URLSession? = nil,
       pollInterval: TimeInterval = 3.0) {
    if let session {
      self.session = session
    } else {
      let cfg = URLSessionConfiguration.default
      cfg.timeoutIntervalForRequest = 15
      cfg.timeoutIntervalForResource = 30
      self.session = URLSession(configuration: cfg)
    }
    self.pollInterval = pollInterval
  }

  func start() {
    guard Config.Telegram.isConfigured && Config.Telegram.isEnabled else {
      Logger.telegram.debug("Telegram not configured, command polling disabled")
      return
    }

    // Seed lastUpdateId from newest update so cold start / token change doesn't replay backlog.
    seedLastUpdateId { [weak self] in
      guard let self else { return }
      self.seeded = true
      self.schedulePolling(initialDeadline: .now())
      Logger.telegram.info("Command polling started")
      ActivityLog.logAsync(.telegram, "Command polling started")
    }
  }

  func stop() {
    timer?.cancel()
    timer = nil
    // Reset so bot-token change doesn't strand us with stale offset for a different bot.
    lastUpdateId = nil
    seeded = false
    Logger.telegram.info("Command polling stopped")
  }

  func pause() {
    timer?.cancel()
    timer = nil
    Logger.telegram.info("Command polling paused for sleep")
  }

  func resume() {
    guard Config.Telegram.isConfigured && Config.Telegram.isEnabled else { return }
    guard timer == nil else { return }
    schedulePolling(initialDeadline: .now() + pollInterval)
    Logger.telegram.info("Command polling resumed after wake")
  }

  /// Fetches the most recent update with offset=-1 to set lastUpdateId, so historical
  /// commands (e.g., a /stop from last week) do not fire on cold start.
  private func seedLastUpdateId(completion: @escaping @MainActor () -> Void) {
    guard let botToken = Config.Telegram.botToken,
          let url = TelegramAPI.updatesURL(botToken: botToken, offset: -1, timeout: 0) else {
      completion()
      return
    }

    session.dataTask(with: url) { [weak self] data, _, _ in
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          guard let self else { return }
          if let data,
             let results = TelegramAPI.parseUpdates(data),
             let updateId = results.last?["update_id"] as? Int {
            self.lastUpdateId = updateId
          }
          completion()
        }
      }
    }.resume()
  }

  private func schedulePolling(initialDeadline: DispatchTime) {
    let newTimer = DispatchSource.makeTimerSource(queue: .main)
    newTimer.schedule(deadline: initialDeadline, repeating: pollInterval)
    newTimer.setEventHandler { [weak self] in
      MainActor.assumeIsolated {
        self?.pollUpdates()
      }
    }
    newTimer.resume()
    timer = newTimer
  }

  private func pollUpdates() {
    guard seeded else { return }
    guard !isPolling else { return }
    guard let botToken = Config.Telegram.botToken,
          let chatId = Config.Telegram.chatId else { return }

    let offset = lastUpdateId.map { $0 + 1 }
    guard let url = TelegramAPI.updatesURL(botToken: botToken, offset: offset) else { return }

    isPolling = true

    let task = session.dataTask(with: url) { [weak self] data, _, error in
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          guard let self else { return }
          defer { self.isPolling = false }
          if let error {
            Logger.telegram.debug("Poll error: \(NetworkRetry.redact(error.localizedDescription))")
            return
          }
          guard let data else { return }
          self.parseUpdates(data, chatId: chatId)
        }
      }
    }
    task.resume()
  }

  private func parseUpdates(_ data: Data, chatId: String) {
    guard let results = TelegramAPI.parseUpdates(data) else { return }

    for update in results {
      if let updateId = update["update_id"] as? Int {
        lastUpdateId = updateId
      }

      guard let (messageChatId, text) = TelegramAPI.extractMessage(from: update),
            messageChatId == chatId else { continue }

      if let command = parseCommand(text) {
        Logger.telegram.info("Received command: \(text)")
        ActivityLog.logAsync(.telegram, "Received command: \(text)")
        delegate?.telegramCommandReceived(command)
      }
    }
  }

  private func parseCommand(_ text: String) -> TelegramCommand? {
    let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()

    if let command = TelegramCommand(rawValue: trimmed) {
      return command
    }

    // Strip emoji/variant-selector characters so "🔴 Disable" matches "disable" and
    // "🔴︎ Disable" (with variant selector) still matches.
    let stripped = trimmed.unicodeScalars
      .filter { !$0.properties.isEmoji && !($0.value >= 0xFE00 && $0.value <= 0xFE0F) }
      .reduce(into: "") { $0.append(Character($1)) }
      .trimmingCharacters(in: .whitespaces)

    switch stripped {
    case "safe": return .safe
    case "status": return .status
    case "enable": return .enable
    case "disable": return .disable
    case "alarm": return .alarm
    case "stop alarm": return .stopalarm
    default: return nil
    }
  }
}
