import AVFoundation
import os.log

final class AlarmAudioManager {
  static let shared = AlarmAudioManager()

  private var player: AVAudioPlayer?
  private var audioEngine: AVAudioEngine?
  private var sourceNode: AVAudioSourceNode?
  private(set) var isPlaying = false

  private init() {}

  func play() {
    guard !isPlaying else { return }
    isPlaying = true

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

    Logger.system.info("Alarm stopped")
    ActivityLog.logAsync(.system, "Alarm stopped")
  }

  func previewSiren() {
    guard audioEngine == nil else { return }

    let engine = AVAudioEngine()
    let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    var phase: Double = 0
    var time: Double = 0

    let source = AVAudioSourceNode { _, _, frameCount, bufferList -> OSStatus in
      let buffer = UnsafeMutableAudioBufferListPointer(bufferList)
      for frame in 0..<Int(frameCount) {
        let sweep = (1.0 + sin(2.0 * .pi * time / 1.2)) / 2.0
        let freq = 620.0 + (1050.0 - 620.0) * sweep
        let sample = Float(sin(phase)) * 0.4
        buffer[0].mData?.assumingMemoryBound(to: Float.self)[frame] = sample
        phase += 2.0 * .pi * freq / 44100.0
        if phase > 2.0 * .pi { phase -= 2.0 * .pi }
        time += 1.0 / 44100.0
      }
      return noErr
    }

    engine.attach(source)
    engine.connect(source, to: engine.mainMixerNode, format: format)

    do {
      try engine.start()
      self.audioEngine = engine
      self.sourceNode = source
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
        self?.audioEngine?.stop()
        self?.audioEngine = nil
        self?.sourceNode = nil
      }
    } catch {}
  }

  // MARK: - Siren (synthesized)

  private func playSiren(volume: Float) {
    let sampleRate: Double = 44100
    let lowFreq: Double = 620
    let highFreq: Double = 1050
    let sweepPeriod: Double = 1.2

    var phase: Double = 0
    var time: Double = 0

    let engine = AVAudioEngine()
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

    let source = AVAudioSourceNode { _, _, frameCount, bufferList -> OSStatus in
      let buffer = UnsafeMutableAudioBufferListPointer(bufferList)
      for frame in 0..<Int(frameCount) {
        let sweep = (1.0 + sin(2.0 * .pi * time / sweepPeriod)) / 2.0
        let freq = lowFreq + (highFreq - lowFreq) * sweep
        let sample = Float(sin(phase))
        buffer[0].mData?.assumingMemoryBound(to: Float.self)[frame] = sample
        phase += 2.0 * .pi * freq / sampleRate
        if phase > 2.0 * .pi { phase -= 2.0 * .pi }
        time += 1.0 / sampleRate
      }
      return noErr
    }

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
      isPlaying = false
    }
  }

  // MARK: - System Sound

  private func playSystemSound(_ soundName: String, volume: Float) {
    let url = URL(fileURLWithPath: "/System/Library/Sounds/\(soundName).aiff")
    guard FileManager.default.fileExists(atPath: url.path) else {
      Logger.system.error("Alarm sound not found: \(soundName)")
      isPlaying = false
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
      isPlaying = false
    }
  }
}
