import Foundation

private enum UpdateType {
  case initial
  case tracking
}

extension TheftProtectionService {
  func startTracking() {
    trackingTimer = DispatchSource.makeTimerSource(queue: .main)
    trackingTimer?.schedule(deadline: .now() + Config.Tracking.interval, repeating: Config.Tracking.interval)
    trackingTimer?.setEventHandler { [weak self] in
      MainActor.assumeIsolated {
        self?.sendUpdate(type: .tracking)
      }
    }
    trackingTimer?.resume()
  }

  func stopTracking() {
    trackingTimer?.cancel()
    trackingTimer = nil
  }

  func sendInitialTheftUpdate() {
    sendUpdate(type: .initial)
  }

  fileprivate func sendUpdate(type: UpdateType) {
    updateCount += 1

    deviceInfoCollector.collect { [weak self] info in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.deliverUpdate(type: type, info: info)
      }
    }
  }

  fileprivate func deliverUpdate(type: UpdateType, info: DeviceInfo) {
    let prefix: String
    switch type {
    case .initial:
      let reason = currentTrigger?.description ?? "Unknown"
      prefix = "🚨 <b>THEFT MODE ACTIVATED</b>\n⚠️ <b>Trigger:</b> \(reason)\n\n"
    case .tracking:
      prefix = "📡 <b>TRACKING UPDATE #\(updateCount)</b>\n\n"
      ActivityLog.logAsync(.theft, "Tracking update #\(updateCount) sent")
    }

    let keyboard: TelegramKeyboard = AlarmAudioManager.shared.isPlaying ? .theftModeAlarmOn : .theftMode
    let episode = theftEpisodeId
    notificationService.send(
      message: prefix + info.formattedMessage,
      keyboard: keyboard
    ) { [weak self] success in
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          guard let self,
                self.state == .theftMode,
                self.theftEpisodeId == episode else { return }
          if success {
            self.telegramSucceededInTheftMode = true
            self.cancelOfflineSirenTimer()
          } else {
            self.scheduleOfflineSiren()
          }
        }
      }
    }
  }

  fileprivate func scheduleOfflineSiren() {
    let settings = SettingsService.shared
    guard settings.offlineSirenEnabled, settings.behaviorAlarm,
          !telegramSucceededInTheftMode else { return }
    guard offlineSirenTimer == nil else { return }
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + 10)
    timer.setEventHandler { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.state == .theftMode else { return }
        AlarmAudioManager.shared.play()
        ActivityLog.logAsync(.theft, "Offline siren triggered (Telegram unreachable)")
      }
    }
    offlineSirenTimer = timer
    timer.resume()
  }

  func cancelOfflineSirenTimer() {
    offlineSirenTimer?.cancel()
    offlineSirenTimer = nil
  }
}
