import AppKit
import Foundation
import os.log

enum ProtectionState: Sendable {
  case disabled
  case enabled
  case enabledBluetooth
  case theftMode
}

enum TheftTrigger: Sendable {
  case lidClosed
  case powerDisconnected
  case motionDetected(String)

  var description: String {
    switch self {
    case .lidClosed: return "Lid closed"
    case .powerDisconnected: return "Power disconnected"
    case .motionDetected(let detail):
      return detail.isEmpty ? "Motion detected" : "Motion detected (\(detail))"
    }
  }
}

@MainActor
protocol TheftProtectionDelegate: AnyObject {
  func theftProtectionStateDidChange(_ service: TheftProtectionService, state: ProtectionState)
  func theftProtectionShortcutTriggered(_ service: TheftProtectionService)
  func theftProtectionBluetoothShortcutTriggered(_ service: TheftProtectionService)
}

@MainActor
final class TheftProtectionService {
  // Daemon connection state — mutated only by TheftProtectionService
  // and its +Daemon extension (same module). Readable elsewhere.
  @MainActor static var daemonConnected = false
  @MainActor static var daemonVersion: String?
  @MainActor static var helperNeedsUpdate = false
  @MainActor static var helperDisconnectedForUpdate = false
  @MainActor static var helperAccessibilityGranted = false
  @MainActor static var daemonMotionSupported = true

  weak var delegate: TheftProtectionDelegate?

  let notificationService: NotificationService
  let deviceInfoCollector: DeviceInfoCollecting
  let sleepPrevention: SleepPrevention
  let lidMonitor: LidMonitorService
  let commandService: TelegramCommandService
  private let sleepWakeService: SleepWakeService
  let powerMonitor: PowerMonitorService
  let daemonClient: DaemonIPC
  private let globalShortcutService = GlobalShortcutService()
  let bluetoothProximityService = BluetoothProximityService()
  let camera: CameraCapturing = CameraCaptureService.shared
  let theftStateStore = TheftStateStore(directory: AppPaths.supportDirectory)
  let outbox = TrackingOutbox(directory: AppPaths.supportDirectory)
  /// Max photos sent on a single reconnect/backlog flush; older queued photos are dropped.
  static let reconnectPhotoCap = 3
  var isFlushingOutbox = false
  var inFlightPhotoIDs: Set<String> = []

  var lastManualDisarmTime: Date?
  var lastArmTime: Date?
  var trackingTimer: DispatchSourceTimer?
  var updateCount = 0
  private(set) var currentTrigger: TheftTrigger?
  private var stateBeforeTheft: ProtectionState?
  var offlineSirenTimer: DispatchSourceTimer?
  var telegramSucceededInTheftMode = false
  private var helperInstallGeneration = 0
  var theftEpisodeId = 0
  var bleAutoDisarmArmed = false
  // Blocks clamshell-sleep theft when a lid-close was suppressed by ext display.
  var suppressedLidClose = false
  private var screenUnlockObserver: NSObjectProtocol?

  /// Grace period after arming during which motion triggers are suppressed.
  static let motionArmGrace: TimeInterval = 3

  private(set) var state: ProtectionState = .disabled

  init(notificationService: NotificationService? = nil,
       deviceInfoCollector: DeviceInfoCollecting? = nil,
       sleepPrevention: SleepPrevention? = nil,
       lidMonitor: LidMonitorService? = nil,
       commandService: TelegramCommandService? = nil,
       sleepWakeService: SleepWakeService? = nil,
       powerMonitor: PowerMonitorService? = nil,
       daemonClient: DaemonIPC? = nil) {
    self.notificationService = notificationService ?? TelegramService()
    self.deviceInfoCollector = deviceInfoCollector ?? DeviceInfoCollector()
    self.sleepPrevention = sleepPrevention ?? SleepPreventionService()
    self.lidMonitor = lidMonitor ?? LidMonitorService()
    self.commandService = commandService ?? TelegramCommandService()
    self.sleepWakeService = sleepWakeService ?? SleepWakeService()
    self.powerMonitor = powerMonitor ?? PowerMonitorService()
    self.daemonClient = daemonClient ?? DaemonIPCClient()

    self.lidMonitor.delegate = self
    self.commandService.delegate = self
    self.sleepWakeService.delegate = self
    self.powerMonitor.delegate = self
    self.globalShortcutService.delegate = self
    self.bluetoothProximityService.delegate = self
    if let client = self.daemonClient as? DaemonIPCClient {
      client.delegate = self
    }

    installNotificationObservers()
  }

  private func installNotificationObservers() {
    let center = NotificationCenter.default
    center.addObserver(forName: .shortcutSettingsChanged, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.globalShortcutService.restart() }
    }
    center.addObserver(forName: .motionSettingsChanged, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.handleMotionSettingsChange() }
    }
    center.addObserver(forName: .bluetoothSettingsChanged, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        if SettingsService.shared.bluetoothAutoArmEnabled {
          self?.bluetoothProximityService.restart()
        } else {
          self?.bluetoothProximityService.stop()
        }
      }
    }
    center.addObserver(forName: .telegramSettingsChanged, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.commandService.stop()
        self?.commandService.start()
        if SettingsService.shared.telegramEnabled {
          self?.deviceInfoCollector.warmUp()
        }
      }
    }
    center.addObserver(forName: .helperStatusRequested, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.daemonClient.isConnected else { return }
        self.daemonClient.getStatus()
      }
    }
    center.addObserver(forName: .helperUpdateDismissed, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.handleHelperUpdateDismissed() }
    }
    center.addObserver(forName: .helperInstallCompleted, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.handleHelperInstallCompleted() }
    }
  }

  private func handleHelperUpdateDismissed() {
    daemonClient.disconnect()
    TheftProtectionService.helperDisconnectedForUpdate = true
    TheftProtectionService.daemonConnected = false
    TheftProtectionService.daemonVersion = nil
    NotificationCenter.default.post(name: .daemonConnectionChanged, object: nil)
    Logger.daemon.warning("Disconnected from helper — required update was dismissed")
    ActivityLog.logAsync(.system, "Helper disconnected — update required but dismissed")
  }

  private func handleHelperInstallCompleted() {
    // Retry a few times — helper may not be running yet after manual install.
    // Track a generation so stale retries from a prior install event bail out.
    helperInstallGeneration &+= 1
    let gen = helperInstallGeneration
    for delay in [0.0, 2.0, 5.0, 10.0] {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        MainActor.assumeIsolated {
          guard let self,
                gen == self.helperInstallGeneration,
                !self.daemonClient.isConnected else { return }
          self.daemonClient.reconnectNow()
        }
      }
    }
  }

  func start() {
    if SettingsService.shared.telegramEnabled {
      deviceInfoCollector.warmUp()
    }
    commandService.start()
    sleepWakeService.start()
    globalShortcutService.start()
    daemonClient.connect()
    if SettingsService.shared.bluetoothAutoArmEnabled {
      bluetoothProximityService.start()
    }

    screenUnlockObserver = DistributedNotificationCenter.default().addObserver(
      forName: NSNotification.Name("com.apple.screenIsUnlocked"),
      object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.state == .theftMode else { return }
        Logger.theft.info("Screen unlocked — deactivating theft mode")
        ActivityLog.logAsync(.theft, "Screen unlocked — owner authenticated")
        self.deactivateTheftMode()
      }
    }

    Logger.theft.info("Started (protection disabled)")
  }

  func shutdown() {
    commandService.stop()
    sleepWakeService.stop()
    lidMonitor.stop()
    powerMonitor.stop()
    globalShortcutService.stop()
    bluetoothProximityService.stop()
    stopTracking()
    cancelOfflineSirenTimer()
    sleepPrevention.disable()
    if let observer = screenUnlockObserver {
      DistributedNotificationCenter.default().removeObserver(observer)
      screenUnlockObserver = nil
    }
    daemonClient.disablePmset()
    daemonClient.disablePowerButton()
    daemonClient.disableMotionMonitoring()
    daemonClient.hideLockScreen()
    daemonClient.disconnect()
  }

  func activeTriggerNames() -> [String] {
    let settings = SettingsService.shared
    var result: [String] = []
    if settings.triggerLidClose { result.append("lid close") }
    if settings.triggerPowerDisconnect { result.append("power disconnect") }
    if settings.triggerPowerButton { result.append("power button") }
    if settings.triggerMotionDetect { result.append("motion") }
    return result
  }

  func activeBehaviorNames() -> [String] {
    let settings = SettingsService.shared
    var result: [String] = []
    if settings.behaviorSleepPrevention { result.append("sleep prevention") }
    if settings.behaviorLidCloseSleep { result.append("lid-close sleep prevention") }
    if settings.behaviorShutdownBlocking { result.append("shutdown blocking") }
    if settings.behaviorLockScreen { result.append("lock screen") }
    if settings.behaviorAlarm {
      result.append(settings.behaviorAutoAlarm ? "alarm (auto)" : "alarm")
    }
    return result
  }

  private func startMonitors() {
    let settings = SettingsService.shared
    if settings.behaviorSleepPrevention {
      sleepPrevention.enable()
    }
    if settings.triggerLidClose { lidMonitor.start() }
    if settings.triggerPowerDisconnect { powerMonitor.start() }

    // Daemon features
    if settings.behaviorLidCloseSleep { daemonClient.enablePmset() }
    if settings.triggerPowerButton { daemonClient.enablePowerButton() }
    if settings.triggerMotionDetect && daemonClient.motionSupported {
      daemonClient.enableMotionMonitoring()
    }
    lastArmTime = Date()
  }

  /// Re-arm motion monitoring with a fresh baseline. Called after returning
  /// from theft mode — the laptop may have been repositioned while in theft
  /// mode, so the old baseline would cause an immediate re-trigger.
  func recalibrateMotion() {
    guard SettingsService.shared.triggerMotionDetect && daemonClient.motionSupported else { return }
    daemonClient.disableMotionMonitoring()
    daemonClient.enableMotionMonitoring()
    lastArmTime = Date()
  }

  /// Apply a mid-arm toggle of the motion setting.
  private func handleMotionSettingsChange() {
    guard state == .enabled || state == .enabledBluetooth else { return }
    if SettingsService.shared.triggerMotionDetect && daemonClient.motionSupported {
      daemonClient.enableMotionMonitoring()
      lastArmTime = Date()
    } else {
      daemonClient.disableMotionMonitoring()
    }
  }

  func enableProtection(notify: Bool = true, lockScreen: Bool = false) {
    guard state == .disabled else { return }

    state = .enabled

    if lockScreen {
      self.lockScreen()
    }
    startMonitors()
    Logger.theft.info("Protection enabled")
    ActivityLog.logAsync(.armed, "Protection enabled")

    if notify && SettingsService.shared.notifyProtectionToggle {
      let triggers = activeTriggerNames()
      let behaviors = activeBehaviorNames()
      var message = "🟢 <b>PROTECTION ENABLED</b>\n\n"
      message += "⚡️ <b>Triggers:</b> \(triggers.isEmpty ? "none" : triggers.joined(separator: ", "))\n"
      message += "🛡 <b>Behaviors:</b> \(behaviors.isEmpty ? "none" : behaviors.joined(separator: ", "))"

      notificationService.send(
        message: message,
        keyboard: .enabled,
        completion: nil
      )
    }

    delegate?.theftProtectionStateDidChange(self, state: .enabled)
  }

  func enableProtectionBluetooth() {
    guard state == .disabled else { return }

    state = .enabledBluetooth
    bleAutoDisarmArmed = true

    if SettingsService.shared.lockScreenOnBluetoothArm {
      self.lockScreen()
    }
    startMonitors()
    Logger.theft.info("Protection enabled via Bluetooth auto-arm")
    ActivityLog.logAsync(.bluetooth, "Protection auto-armed (all devices out of range)")

    if SettingsService.shared.notifyAutoArm {
      notificationService.send(
        message: "📶 <b>PROTECTION AUTO-ARMED</b>\n\nAll trusted Bluetooth devices left range.",
        keyboard: .enabled,
        completion: nil
      )
    }

    delegate?.theftProtectionStateDidChange(self, state: .enabledBluetooth)
  }

  func disableProtection(remote: Bool = false) {
    guard state == .enabled || state == .enabledBluetooth else { return }

    let wasBluetooth = state == .enabledBluetooth
    state = .disabled
    theftStateStore.clear()
    bleAutoDisarmArmed = false
    suppressedLidClose = false
    // Only set cooldown for genuine manual disarms (not bluetooth auto-disarm)
    if !wasBluetooth {
      lastManualDisarmTime = Date()
    }
    lidMonitor.stop()
    powerMonitor.stop()
    sleepPrevention.disable()
    daemonClient.disablePmset()
    daemonClient.disablePowerButton()
    daemonClient.disableMotionMonitoring()
    daemonClient.hideLockScreen()
    lastArmTime = nil
    Logger.theft.info("Protection disabled")

    let method = remote ? "Telegram" : "Touch ID"
    if wasBluetooth && !remote {
      ActivityLog.logAsync(.bluetooth, "Protection auto-disarmed (trusted device returned)")
      if SettingsService.shared.notifyAutoArm {
        notificationService.send(
          message: "📶 <b>PROTECTION AUTO-DISARMED</b>\n\nTrusted Bluetooth device returned.",
          keyboard: .disabled,
          completion: nil
        )
      }
    } else {
      ActivityLog.logAsync(.disarmed, "Protection disabled via \(method)")
      if SettingsService.shared.notifyProtectionToggle {
        notificationService.send(
          message: "🔴 <b>PROTECTION DISABLED</b>\n\nDisabled via \(method).",
          keyboard: .disabled,
          completion: nil
        )
      }
    }

    delegate?.theftProtectionStateDidChange(self, state: .disabled)
  }

  func activateTheftMode(trigger: TheftTrigger) {
    guard state == .enabled || state == .enabledBluetooth else { return }

    stateBeforeTheft = state
    state = .theftMode
    currentTrigger = trigger
    theftStateStore.save(TheftStateRecord(state: "theftMode", trigger: trigger.description, startedAt: Date()))
    updateCount = 0
    theftEpisodeId &+= 1
    outbox.clear()  // fresh incident — discard any leftovers from a prior episode
    inFlightPhotoIDs.removeAll()
    bleAutoDisarmArmed = false
    suppressedLidClose = false
    Logger.theft.warning("THEFT MODE ACTIVATED - \(trigger.description)")
    ActivityLog.logAsync(.theft, "THEFT MODE ACTIVATED - \(trigger.description)")
    // Stop motion monitoring while in theft mode (the main-app gate would
    // drop events anyway, but this saves helper CPU and log spam).
    // On deactivate, recalibrateMotion() restarts it with a fresh baseline.
    daemonClient.disableMotionMonitoring()

    // System lock screen + overlay message
    let settings = SettingsService.shared
    if settings.lockScreenOnTheftMode {
      lockScreen()
    }
    if settings.lockScreenOnTheftMode && settings.behaviorLockScreen {
      let name = settings.contactName ?? ""
      let phone = settings.contactPhone ?? ""
      daemonClient.showLockScreen(contactName: name, contactPhone: phone, message: "STOLEN DEVICE")
    }

    // Auto-play alarm if enabled
    if settings.behaviorAlarm && settings.behaviorAutoAlarm {
      AlarmAudioManager.shared.play()
    }

    // Offline siren: if Telegram not available, play siren immediately
    telegramSucceededInTheftMode = false
    if settings.offlineSirenEnabled && settings.behaviorAlarm
       && (!Config.Telegram.isConfigured || !Config.Telegram.isEnabled) {
      AlarmAudioManager.shared.play()
      ActivityLog.logAsync(.theft, "Offline siren triggered (Telegram not configured/disabled)")
    }

    sendInitialTheftUpdate()
    capturePhotoIfEnabled(caption: "🕵️ <b>Thief photo</b> — theft activated")
    startTracking()

    delegate?.theftProtectionStateDidChange(self, state: .theftMode)
  }

  func deactivateTheftMode(remote: Bool = false) {
    guard state == .theftMode else { return }

    let restoredState = stateBeforeTheft ?? .enabled
    state = restoredState
    stateBeforeTheft = nil
    theftStateStore.clear()
    outbox.clear()  // incident closed by owner — drop undelivered queue + photo sidecars
    inFlightPhotoIDs.removeAll()
    stopTracking()
    updateCount = 0
    currentTrigger = nil
    AlarmAudioManager.shared.stop()
    cancelOfflineSirenTimer()
    telegramSucceededInTheftMode = false
    daemonClient.hideLockScreen()
    recalibrateMotion()  // laptop may have been repositioned during theft
    Logger.theft.info("Theft mode deactivated")

    let method = remote ? "Telegram" : "Touch ID"
    ActivityLog.logAsync(.theft, "Theft mode deactivated via \(method)")

    notificationService.send(
      message: "✅ <b>THEFT MODE DEACTIVATED</b>\n\nOwner authenticated via \(method).",
      keyboard: .enabled,
      completion: nil
    )

    delegate?.theftProtectionStateDidChange(self, state: restoredState)
  }

  /// Called once at launch. If the app was killed/powered-off during theft mode,
  /// re-enter theft mode. Only resumes after a user login (the app launches via
  /// SMAppService login item) — pre-login resume would need a privileged daemon.
  func resumeTheftModeIfNeeded() {
    guard SettingsService.shared.restoreTheftModeEnabled else { return }
    guard state == .disabled else { return }
    guard let record = theftStateStore.load(), record.state == "theftMode" else { return }

    stateBeforeTheft = .enabled
    state = .theftMode
    currentTrigger = nil
    updateCount = 0
    theftEpisodeId &+= 1
    Logger.theft.warning("THEFT MODE RESUMED after power-off")
    ActivityLog.logAsync(.theft, "Theft mode resumed after power-off")

    startMonitors()
    // Mirror activateTheftMode: stop motion monitoring while in theft mode (saves helper CPU/log spam).
    daemonClient.disableMotionMonitoring()

    let settings = SettingsService.shared
    if settings.lockScreenOnTheftMode {
      lockScreen()
    }
    if settings.lockScreenOnTheftMode && settings.behaviorLockScreen {
      let name = settings.contactName ?? ""
      let phone = settings.contactPhone ?? ""
      daemonClient.showLockScreen(contactName: name, contactPhone: phone, message: "STOLEN DEVICE")
    }
    if settings.behaviorAlarm && settings.behaviorAutoAlarm {
      AlarmAudioManager.shared.play()
    }

    telegramSucceededInTheftMode = false
    // Mirror activateTheftMode: if Telegram is unavailable, play the siren immediately.
    if settings.offlineSirenEnabled && settings.behaviorAlarm
       && (!Config.Telegram.isConfigured || !Config.Telegram.isEnabled) {
      AlarmAudioManager.shared.play()
      ActivityLog.logAsync(.theft, "Offline siren triggered (Telegram not configured/disabled)")
    }

    notificationService.send(
      message: "⚠️ <b>DEVICE POWERED BACK ON — THEFT MODE RESUMED</b>\n\nThe device was powered off during theft mode and has just restarted.",
      keyboard: AlarmAudioManager.shared.isPlaying ? .theftModeAlarmOn : .theftMode,
      completion: nil
    )

    sendInitialTheftUpdate()
    capturePhotoIfEnabled(caption: "🕵️ <b>Thief photo</b> — resumed after power-off")
    startTracking()
    delegate?.theftProtectionStateDidChange(self, state: .theftMode)
  }

  /// Captures a thief photo (if enabled + permitted), queues it, and flushes.
  /// Best-effort: any failure is logged and ignored; never blocks tracking.
  func capturePhotoIfEnabled(caption: String) {
    guard state == .theftMode, SettingsService.shared.photoCaptureEnabled else { return }
    camera.capturePhoto { [weak self] data in
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          guard let self, self.state == .theftMode else { return }
          guard let data else {
            ActivityLog.logAsync(.theft, "Thief photo capture failed")
            return
          }
          let id = UUID().uuidString
          guard let filename = self.outbox.storePhoto(data, id: id) else { return }
          self.outbox.enqueue(OutboxItem(id: id, timestamp: Date(), kind: .photo, snapshot: nil,
                                         renderedMessage: caption, photoFilename: filename))
          ActivityLog.logAsync(.theft, "Thief photo captured")
          self.flushOutbox()
        }
      }
    }
  }

  func refreshLocation() {
    deviceInfoCollector.warmUp()
  }

  private func lockScreen() {
    daemonClient.lockScreen()
  }
}
