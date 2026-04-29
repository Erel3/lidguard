import Foundation

extension TheftProtectionService: TelegramCommandDelegate {
  // Telegram commands arrive on `com.lidguard.telegram.commands` (utility
  // queue, intentional). State mutations must happen on main so
  // `currentTrigger` and other state are read/written on a single thread.
  func telegramCommandReceived(_ command: TelegramCommand) {
    DispatchQueue.main.async { [weak self] in
      self?.handleTelegramCommand(command)
    }
  }

  func handleTelegramCommand(_ command: TelegramCommand) {
    switch command {
    case .stop, .safe:
      deactivateTheftMode(remote: true)
    case .status:
      sendStatus()
    case .enable:
      enableProtection(lockScreen: SettingsService.shared.lockScreenOnTelegramEnable)
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
