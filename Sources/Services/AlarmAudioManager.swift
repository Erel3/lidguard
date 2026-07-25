import AVFoundation
import os.log

@MainActor
final class AlarmAudioManager {
  static let shared = AlarmAudioManager()

  private let audioController = SystemAudioController()
  private var player: AVAudioPlayer?
  private var audioEngine: AVAudioEngine?
  private var sourceNode: AVAudioSourceNode?
  private(set) var isPlaying = false
  private var previewActive = false
  private var previewGeneration: Int = 0

  private init() {
    audioController.restoreSystemVolumeIfNeeded()
  }

  func play() {
    guard !isPlaying else { return }
    isPlaying = true

    // Must happen before playSiren/playSystemSound claims `audioEngine`.
    invalidatePreview()

    audioController.captureAndMaximize { [weak self] in
      self?.isPlaying ?? false
    }

    let soundName = SettingsService.shared.alarmSound
    let volume = Float(SettingsService.shared.alarmVolume) / 100.0

    if soundName == "Siren" {
      playSiren(volume: volume)
    } else {
      playSystemSound(soundName, volume: volume)
    }
  }

  func stop() {
    guard isPlaying else { return }
    isPlaying = false

    player?.stop()
    player = nil
    audioEngine?.stop()
    audioEngine = nil
    sourceNode = nil

    audioController.restore()

    Logger.system.info("Alarm stopped")
    ActivityLog.logAsync(.system, "Alarm stopped")
  }

  func previewSiren() {
    guard !previewActive, audioEngine == nil else { return }
    guard let format = AVAudioFormat(standardFormatWithSampleRate: SirenSynth.sampleRate, channels: 1) else {
      Logger.system.error("previewSiren: AVAudioFormat init failed")
      return
    }
    previewActive = true
    previewGeneration &+= 1
    let gen = previewGeneration

    let engine = AVAudioEngine()
    let source = SirenSynth.makeSourceNode(amplitude: 0.28)

    engine.attach(source)
    engine.connect(source, to: engine.mainMixerNode, format: format)

    do {
      try engine.start()
      self.audioEngine = engine
      self.sourceNode = source
    } catch {
      previewActive = false
      return
    }

    // The identity check is not redundant with the generation check — it is the
    // one that cannot be defeated by a future caller forgetting to bump the
    // generation, which is exactly how this closure came to tear down the real
    // alarm engine.
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self, weak engine] in
      guard let self = self, gen == self.previewGeneration,
            let engine = engine, self.audioEngine === engine else { return }
      self.audioEngine?.stop()
      self.audioEngine = nil
      self.sourceNode = nil
      self.previewActive = false
    }
  }

  /// Disarms an in-flight preview teardown and releases its engine.
  ///
  /// `previewSiren()` schedules a +1.5s closure that stops and nils `audioEngine`.
  /// The real alarm reuses that same field, so without this the preview's timer
  /// tears down the ALARM engine about a second into a genuine theft siren —
  /// leaving `isPlaying == true` (menu and Telegram keyboard both offer "Stop
  /// Alarm") with nothing audible, and `stop()` a no-op on the already-nil engine.
  private func invalidatePreview() {
    guard previewActive else { return }
    previewGeneration &+= 1     // disarms the pending teardown
    previewActive = false
    // Still the preview's engine at this point — the caller has not claimed the
    // field yet — so stopping it here is what keeps it from leaking.
    audioEngine?.stop()
    audioEngine = nil
    sourceNode = nil
  }

  // MARK: - Siren

  private func playSiren(volume: Float) {
    guard let format = AVAudioFormat(standardFormatWithSampleRate: SirenSynth.sampleRate, channels: 1) else {
      Logger.system.error("playSiren: AVAudioFormat init failed — aborting siren")
      ActivityLog.logAsync(.system, "Alarm failed: audio format init")
      revertOnFailure()
      return
    }

    let engine = AVAudioEngine()
    let source = SirenSynth.makeSourceNode(amplitude: 0.7)

    engine.attach(source)
    engine.connect(source, to: engine.mainMixerNode, format: format)
    engine.mainMixerNode.outputVolume = volume

    do {
      try engine.start()
      self.audioEngine = engine
      self.sourceNode = source
      Logger.system.info("Siren alarm started")
      ActivityLog.logAsync(.system, "Alarm started: Siren")
    } catch {
      Logger.system.error("Failed to start siren: \(error.localizedDescription)")
      revertOnFailure()
    }
  }

  // MARK: - System Sound

  private func playSystemSound(_ soundName: String, volume: Float) {
    let url = URL(fileURLWithPath: "/System/Library/Sounds/\(soundName).aiff")
    guard FileManager.default.fileExists(atPath: url.path) else {
      Logger.system.error("Alarm sound not found: \(soundName)")
      revertOnFailure()
      return
    }

    do {
      player = try AVAudioPlayer(contentsOf: url)
      player?.volume = volume
      player?.numberOfLoops = -1
      player?.play()
      Logger.system.info("Alarm started: \(soundName)")
      ActivityLog.logAsync(.system, "Alarm started: \(soundName)")
    } catch {
      Logger.system.error("Failed to play alarm: \(error.localizedDescription)")
      revertOnFailure()
    }
  }

  private func revertOnFailure() {
    isPlaying = false
    audioController.restore()
  }
}
