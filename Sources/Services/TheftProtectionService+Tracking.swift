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
  /// text items, then ALL queued media (none dropped), removing each on success. On
  /// failure items remain queued and the offline siren is scheduled.
  func flushOutbox() {
    guard state == .theftMode, !isFlushingOutbox else { return }
    let plan = OutboxFlush.plan(items: outbox.items)

    guard let message = plan.message else {
      flushMedia(ids: plan.mediaItemIDs)
      return
    }

    isFlushingOutbox = true
    let keyboard: TelegramKeyboard = AlarmAudioManager.shared.isPlaying ? .theftModeAlarmOn : .theftMode
    let episode = theftEpisodeId
    notificationService.send(message: message, keyboard: keyboard) { [weak self] success in
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          guard let self else { return }
          // Bail on a stale completion (disarmed / new episode) BEFORE touching the
          // flag, so it can't clear a new episode's in-flight flush — mirrors
          // sendNextMedia's ordering.
          guard self.state == .theftMode, self.theftEpisodeId == episode else { return }
          self.isFlushingOutbox = false
          if success {
            self.outbox.remove(ids: plan.textItemIDs)
            self.cancelOfflineSirenTimer()
            self.flushMedia(ids: plan.mediaItemIDs)
            self.flushOutbox()  // deliver anything enqueued during the in-flight send
          } else {
            self.scheduleOfflineSiren()
          }
        }
      }
    }
  }

  /// Drains queued media ONE AT A TIME, oldest first, with a gap between uploads so a
  /// backlog doesn't burst-send and trip Telegram's rate limit. On a send failure the item
  /// stays queued and draining stops; the next tracking tick re-attempts.
  func flushMedia(ids: [String]) {
    guard state == .theftMode, !isSendingMedia else { return }
    sendNextMedia(remaining: ids)
  }

  private func sendNextMedia(remaining: [String]) {
    guard state == .theftMode else { isSendingMedia = false; return }
    let queued = outbox.items
      .filter { remaining.contains($0.id) && ($0.kind == .photo || $0.kind == .video) }
      .sorted { $0.timestamp < $1.timestamp }
    guard let item = queued.first else { isSendingMedia = false; return }
    let rest = remaining.filter { $0 != item.id }
    isSendingMedia = true

    let keyboard: TelegramKeyboard = AlarmAudioManager.shared.isPlaying ? .theftModeAlarmOn : .theftMode
    let caption = item.renderedMessage ?? "🕵️ Thief media"
    let episode = theftEpisodeId
    let onResult: @Sendable (Bool) -> Void = { [weak self] success in
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          guard let self else { return }
          // Stale completion (disarmed / new episode): just bail. activate/deactivate already
          // reset isSendingMedia, so don't clobber a live new-episode drain's flag here.
          guard self.state == .theftMode, self.theftEpisodeId == episode else { return }
          if success {
            self.outbox.remove(ids: [item.id])
            // Pace the next upload to stay under the rate limit.
            DispatchQueue.main.asyncAfter(deadline: .now() + TheftProtectionService.mediaSendGap) { [weak self] in
              MainActor.assumeIsolated { self?.sendNextMedia(remaining: rest) }
            }
          } else {
            self.isSendingMedia = false   // leave queued; next tracking tick retries
          }
        }
      }
    }

    if item.kind == .video {
      guard let fileURL = outbox.mediaFileURL(for: item),
            FileManager.default.fileExists(atPath: fileURL.path) else {
        outbox.remove(ids: [item.id]); sendNextMedia(remaining: rest); return
      }
      notificationService.sendVideo(fileURL: fileURL, caption: caption, keyboard: keyboard, completion: onResult)
    } else {
      guard let data = outbox.mediaData(for: item) else {
        outbox.remove(ids: [item.id]); sendNextMedia(remaining: rest); return
      }
      notificationService.sendPhoto(jpeg: data, caption: caption, keyboard: keyboard, completion: onResult)
    }
  }

  fileprivate func scheduleOfflineSiren() {
    // Fires whenever Telegram is CURRENTLY unreachable — including after the
    // device goes dark mid-episode. A successful send cancels the timer
    // (cancelOfflineSirenTimer), so this reflects live reachability, not whether
    // we ever reached Telegram this episode.
    let settings = SettingsService.shared
    guard settings.offlineSirenEnabled, settings.behaviorAlarm else { return }
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
