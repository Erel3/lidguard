import AppKit
import Foundation
import os.log

enum ProtectionState {
  case disabled
  case enabled
  case theftMode
}

enum TheftTrigger {
  case lidClosed
  case powerDisconnected

  var description: String {
    switch self {
    case .lidClosed: return "Lid closed"
    case .powerDisconnected: return "Power disconnected"
    }
  }
}

protocol TheftProtectionDelegate: AnyObject {
  func theftProtectionStateDidChange(_ service: TheftProtectionService, state: ProtectionState)
}

final class TheftProtectionService {
  weak var delegate: TheftProtectionDelegate?

  private let notificationService: NotificationService
  private let pushover: PushoverService
  private let deviceInfoCollector: DeviceInfoCollecting
  private let sleepPrevention: SleepPrevention
  private let lidMonitor: LidMonitorService
  private let commandService: TelegramCommandService
  private let sleepWakeService: SleepWakeService
  private let powerMonitor: PowerMonitorService
  private let powerButtonMonitor = PowerButtonMonitor()
  private let pmsetService = PmsetService.shared

  private var trackingTimer: DispatchSourceTimer?
  private let trackingQueue = DispatchQueue(label: "com.lidguard.tracking", qos: .userInitiated)
  private var updateCount = 0
  private var currentTrigger: TheftTrigger?

  private(set) var state: ProtectionState = .disabled

  init(notificationService: NotificationService = TelegramService(),
       pushover: PushoverService = PushoverService(),
       deviceInfoCollector: DeviceInfoCollecting = DeviceInfoCollector(),
       sleepPrevention: SleepPrevention = SleepPreventionService(),
       lidMonitor: LidMonitorService = LidMonitorService(),
       commandService: TelegramCommandService = TelegramCommandService(),
       sleepWakeService: SleepWakeService = SleepWakeService(),
       powerMonitor: PowerMonitorService = PowerMonitorService()) {
    self.notificationService = notificationService
    self.pushover = pushover
    self.deviceInfoCollector = deviceInfoCollector
    self.sleepPrevention = sleepPrevention
    self.lidMonitor = lidMonitor
    self.commandService = commandService
    self.sleepWakeService = sleepWakeService
    self.powerMonitor = powerMonitor

    self.lidMonitor.delegate = self
    self.commandService.delegate = self
    self.sleepWakeService.delegate = self
    self.powerMonitor.delegate = self
    self.powerButtonMonitor.delegate = self
  }

  func start() {
    deviceInfoCollector.warmUp()
    commandService.start()
    sleepWakeService.start()
    Logger.theft.info("Started (protection disabled)")
  }

  func shutdown() {
    powerMonitor.stop()
    pmsetService.disable()
  }

  func enableProtection(notify: Bool = true) {
    guard state == .disabled else { return }

    let settings = SettingsService.shared
    state = .enabled
    if settings.behaviorSleepPrevention {
      sleepPrevention.enable()
      pmsetService.enable()
    }
    if settings.triggerLidClose { lidMonitor.start() }
    if settings.triggerPowerDisconnect { powerMonitor.start() }
    if settings.triggerPowerButton { powerButtonMonitor.start() }
    Logger.theft.info("Protection enabled")
    ActivityLog.logAsync(.armed, "Protection enabled")

    if notify {
      notificationService.send(
        message: "🟢 <b>PROTECTION ENABLED</b>\n\nMonitoring for lid close.",
        keyboard: .enabled,
        completion: nil
      )
    }

    delegate?.theftProtectionStateDidChange(self, state: .enabled)
  }

  func disableProtection(remote: Bool = false) {
    guard state == .enabled else { return }

    state = .disabled
    lidMonitor.stop()
    powerMonitor.stop()
    powerButtonMonitor.stop()
    sleepPrevention.disable()
    pmsetService.disable()
    Logger.theft.info("Protection disabled")

    let method = remote ? "Telegram" : "Touch ID"
    ActivityLog.logAsync(.disarmed, "Protection disabled via \(method)")

    notificationService.send(
      message: "🔴 <b>PROTECTION DISABLED</b>\n\nDisabled via \(method).",
      keyboard: .disabled,
      completion: nil
    )

    delegate?.theftProtectionStateDidChange(self, state: .disabled)
  }

  func activateTheftMode(trigger: TheftTrigger) {
    guard state != .theftMode else { return }

    state = .theftMode
    currentTrigger = trigger
    updateCount = 0
    Logger.theft.warning("THEFT MODE ACTIVATED - \(trigger.description)")
    ActivityLog.logAsync(.theft, "THEFT MODE ACTIVATED - \(trigger.description)")

    // Lock screen and show message
    if SettingsService.shared.behaviorLockScreen {
      lockScreen()
      LockScreenMessageService.shared.show(
        message: "STOLEN DEVICE",
        onUnlock: { [weak self] in
          self?.deactivateTheftMode()
        }
      )
    }

    // Immediate Pushover alert (fast)
    pushover.send(message: "🚨 THEFT MODE ACTIVATED - \(trigger.description)")

    // Auto-play alarm if enabled
    if SettingsService.shared.behaviorAlarm && SettingsService.shared.behaviorAutoAlarm {
      AlarmAudioManager.shared.play()
    }

    sendUpdate(type: .initial)
    startTracking()

    delegate?.theftProtectionStateDidChange(self, state: .theftMode)
  }

  func deactivateTheftMode(remote: Bool = false) {
    guard state == .theftMode else { return }

    state = .enabled
    stopTracking()
    updateCount = 0
    currentTrigger = nil
    AlarmAudioManager.shared.stop()
    LockScreenMessageService.shared.hide()
    Logger.theft.info("Theft mode deactivated")

    let method = remote ? "Telegram" : "Touch ID"
    ActivityLog.logAsync(.theft, "Theft mode deactivated via \(method)")

    notificationService.send(
      message: "✅ <b>THEFT MODE DEACTIVATED</b>\n\nOwner authenticated via \(method).",
      keyboard: .enabled,
      completion: nil
    )

    delegate?.theftProtectionStateDidChange(self, state: .enabled)
  }

  func sendStatus() {
    deviceInfoCollector.collect { [weak self] info in
      guard let self = self else { return }
      let status: String
      let keyboard: TelegramKeyboard

      switch self.state {
      case .disabled:
        status = "🔴 PROTECTION DISABLED"
        keyboard = .disabled
      case .enabled:
        status = "✅ Monitoring"
        keyboard = .enabled
      case .theftMode:
        status = "🚨 THEFT MODE ACTIVE"
        keyboard = .theftMode
      }

      self.notificationService.send(
        message: "<b>STATUS: \(status)</b>\n\n\(info.formattedMessage)",
        keyboard: keyboard,
        completion: nil
      )
    }
  }

  func refreshLocation() {
    deviceInfoCollector.warmUp()
  }

  func sendTestAlert() {
    let keyboard: TelegramKeyboard = state == .disabled ? .disabled : .enabled
    deviceInfoCollector.collect { [weak self] info in
      self?.notificationService.send(
        message: "🧪 <b>TEST ALERT</b>\n\n\(info.formattedMessage)",
        keyboard: keyboard,
        completion: nil
      )
    }
    ActivityLog.logAsync(.system, "Test alert sent")
  }

  func sendShutdownAlert(blocked: Bool) {
    let title = blocked ? "SHUTDOWN BLOCKED" : "POWER BUTTON PRESSED"
    let subtitle = blocked ? "Someone tried to shut down!" : "Device may be force-powered off!"

    deviceInfoCollector.collect { [weak self] info in
      guard let self = self else { return }
      self.notificationService.send(
        message: "🚨 <b>\(title)</b>\n\n⚠️ \(subtitle)\n\n\(info.formattedMessage)",
        keyboard: self.state == .theftMode ? .theftMode : .enabled,
        completion: nil
      )
    }

    pushover.send(message: "🚨 \(title) - \(subtitle)")
  }

  private func startTracking() {
    trackingTimer = DispatchSource.makeTimerSource(queue: trackingQueue)
    trackingTimer?.schedule(deadline: .now() + Config.Tracking.interval, repeating: Config.Tracking.interval)
    trackingTimer?.setEventHandler { [weak self] in
      self?.sendUpdate(type: .tracking)
    }
    trackingTimer?.resume()
  }

  private func stopTracking() {
    trackingTimer?.cancel()
    trackingTimer = nil
  }

  private func sendUpdate(type: UpdateType) {
    updateCount += 1

    deviceInfoCollector.collect { [weak self] info in
      guard let self = self else { return }

      let prefix: String
      switch type {
      case .initial:
        let reason = self.currentTrigger?.description ?? "Unknown"
        prefix = "🚨 <b>THEFT MODE ACTIVATED</b>\n⚠️ <b>Trigger:</b> \(reason)\n\n"
      case .tracking:
        prefix = "📡 <b>TRACKING UPDATE #\(self.updateCount)</b>\n\n"
        ActivityLog.logAsync(.theft, "Tracking update #\(self.updateCount) sent")
      }

      self.notificationService.send(
        message: prefix + info.formattedMessage,
        keyboard: .theftMode,
        completion: nil
      )
    }
  }

  private enum UpdateType {
    case initial
    case tracking
  }

  private func lockScreen() {
    // Use private Login framework API
    let libHandle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY)
    guard libHandle != nil else { return }
    guard let sym = dlsym(libHandle, "SACLockScreenImmediate") else { return }
    typealias LockFunction = @convention(c) () -> Void
    let lock = unsafeBitCast(sym, to: LockFunction.self)
    lock()
  }
}

// MARK: - LidMonitorDelegate
extension TheftProtectionService: LidMonitorDelegate {
  func lidMonitorDidDetectClose(_ monitor: LidMonitorService) {
    guard SettingsService.shared.triggerLidClose else { return }
    ActivityLog.logAsync(.trigger, "Lid closed detected")
    activateTheftMode(trigger: .lidClosed)
  }

  func lidMonitorDidDetectOpen(_ monitor: LidMonitorService) {
    Logger.theft.info("Lid opened - theft mode still active")
    ActivityLog.logAsync(.trigger, "Lid opened - theft mode still active")
  }
}

// MARK: - TelegramCommandDelegate
extension TheftProtectionService: TelegramCommandDelegate {
  func telegramCommandReceived(_ command: TelegramCommand) {
    switch command {
    case .stop, .safe:
      deactivateTheftMode(remote: true)
    case .status:
      sendStatus()
    case .enable:
      enableProtection()
    case .disable:
      disableProtection(remote: true)
    case .alarm:
      guard state == .theftMode else { return }
      guard SettingsService.shared.behaviorAlarm else { return }
      AlarmAudioManager.shared.play()
      notificationService.send(
        message: "🔊 <b>ALARM ACTIVATED</b>",
        keyboard: .theftModeAlarmOn,
        completion: nil
      )
    case .stopalarm:
      AlarmAudioManager.shared.stop()
      let keyboard: TelegramKeyboard = state == .theftMode ? .theftMode : .enabled
      notificationService.send(
        message: "🔇 <b>ALARM STOPPED</b>",
        keyboard: keyboard,
        completion: nil
      )
    }
  }
}

// MARK: - SleepWakeDelegate
extension TheftProtectionService: SleepWakeDelegate {
  func systemWillSleep() {
    ActivityLog.logAsync(.power, "System will sleep")
    // Check lid right before sleep (only if enabled)
    if state == .enabled && SettingsService.shared.triggerLidClose && lidMonitor.isClosed {
      activateTheftMode(trigger: .lidClosed)
    }
  }

  func systemDidWake() {
    ActivityLog.logAsync(.power, "System did wake")
    // On any wake (including DarkWake), check lid and re-enable sleep prevention
    if state == .enabled {
      if SettingsService.shared.behaviorSleepPrevention {
        sleepPrevention.enable()
      }
      if SettingsService.shared.triggerLidClose && lidMonitor.isClosed {
        activateTheftMode(trigger: .lidClosed)
      }
    }
  }

  func shouldDenySleep() -> Bool {
    return state == .theftMode
  }
}

// MARK: - PowerMonitorDelegate
extension TheftProtectionService: PowerMonitorDelegate {
  func powerMonitorDidDetectDisconnect(_ monitor: PowerMonitorService) {
    guard state == .enabled else { return }
    guard SettingsService.shared.triggerPowerDisconnect else { return }
    ActivityLog.logAsync(.trigger, "Power disconnected detected")
    activateTheftMode(trigger: .powerDisconnected)
  }
}

// MARK: - PowerButtonDelegate
extension TheftProtectionService: PowerButtonDelegate {
  func powerButtonPressed() {
    guard state != .disabled else { return }
    guard SettingsService.shared.triggerPowerButton else { return }
    ActivityLog.logAsync(.trigger, "Power button pressed detected")
    sendShutdownAlert(blocked: false)
  }
}
