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
    if type == .tracking,
       PhotoCadence.shouldCaptureOnUpdate(updateCount: updateCount,
                                          everyN: SettingsService.shared.photoCaptureEveryN) {
      capturePhotoIfEnabled(caption: "🕵️ <b>Thief photo</b> — update #\(updateCount)")
    }

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
      ActivityLog.logAsync(.theft, "Tracking update #\(updateCount) queued")
    }

    let item = OutboxItem(
      id: UUID().uuidString,
      timestamp: info.timestamp,
      kind: type == .initial ? .initialUpdate : .trackingUpdate,
      snapshot: DeviceSnapshot(info),
      renderedMessage: prefix + info.formattedMessage,
      mediaFilename: nil
    )
    outbox.enqueue(item)
    flushOutbox()
  }

  /// Sends one text message (single rendered or coalesced summary) for the queued
  /// text items, then the newest photos (cap), removing each on success. On failure
  /// items remain queued and the offline siren is scheduled.
  func flushOutbox() {
    guard state == .theftMode, !isFlushingOutbox else { return }
    let plan = OutboxFlush.plan(items: outbox.items, photoCap: TheftProtectionService.reconnectPhotoCap)
    outbox.remove(ids: plan.photoDropIDs)   // drop stale photos beyond the cap

    guard let message = plan.message else {
      flushMedia(ids: plan.photoItemIDs)
      return
    }

    isFlushingOutbox = true
    let keyboard: TelegramKeyboard = AlarmAudioManager.shared.isPlaying ? .theftModeAlarmOn : .theftMode
    let episode = theftEpisodeId
    notificationService.send(message: message, keyboard: keyboard) { [weak self] success in
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          guard let self else { return }
          self.isFlushingOutbox = false
          guard self.state == .theftMode, self.theftEpisodeId == episode else { return }
          if success {
            self.outbox.remove(ids: plan.textItemIDs)
            self.telegramSucceededInTheftMode = true
            self.cancelOfflineSirenTimer()
            self.flushMedia(ids: plan.photoItemIDs)
            self.flushOutbox()  // deliver anything enqueued during the in-flight send
          } else {
            self.scheduleOfflineSiren()
          }
        }
      }
    }
  }

  func flushMedia(ids: [String]) {
    guard state == .theftMode else { return }
    // Send oldest→newest of the capped set; skip media already in flight; remove on success.
    let items = outbox.items
      .filter { ids.contains($0.id) && ($0.kind == .photo || $0.kind == .video) && !inFlightMediaIDs.contains($0.id) }
      .sorted { $0.timestamp < $1.timestamp }
    guard !items.isEmpty else { return }
    let keyboard: TelegramKeyboard = AlarmAudioManager.shared.isPlaying ? .theftModeAlarmOn : .theftMode
    for item in items {
      let caption = item.renderedMessage ?? "🕵️ Thief media"
      let episode = theftEpisodeId
      let onResult: @Sendable (Bool) -> Void = { [weak self] success in
        DispatchQueue.main.async {
          MainActor.assumeIsolated {
            guard let self else { return }
            self.inFlightMediaIDs.remove(item.id)
            guard self.state == .theftMode, self.theftEpisodeId == episode else { return }
            if success { self.outbox.remove(ids: [item.id]) }
          }
        }
      }
      if item.kind == .video {
        guard let fileURL = outbox.mediaFileURL(for: item) else { outbox.remove(ids: [item.id]); continue }
        inFlightMediaIDs.insert(item.id)
        notificationService.sendVideo(fileURL: fileURL, caption: caption, keyboard: keyboard, completion: onResult)
      } else {
        guard let data = outbox.mediaData(for: item) else { outbox.remove(ids: [item.id]); continue }
        inFlightMediaIDs.insert(item.id)
        notificationService.sendPhoto(jpeg: data, caption: caption, keyboard: keyboard, completion: onResult)
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
