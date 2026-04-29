import AVFoundation

enum SirenSynth {
  static let sampleRate: Double = 44100
  static let lowFreq: Double = 500
  static let highFreq: Double = 1400
  static let sweepPeriod: Double = 0.7

  static func makeSourceNode(amplitude: Float) -> AVAudioSourceNode {
    var phase: Double = 0
    var phase2: Double = 0
    var time: Double = 0

    return AVAudioSourceNode { _, _, frameCount, bufferList -> OSStatus in
      let buffer = UnsafeMutableAudioBufferListPointer(bufferList)
      for frame in 0..<Int(frameCount) {
        let sweep = (1.0 + sin(2.0 * .pi * time / sweepPeriod)) / 2.0
        let freq = lowFreq + (highFreq - lowFreq) * sweep

        let fundamental = sin(phase)
        let harmonic3 = sin(phase * 3.0) * 0.3
        let harmonic5 = sin(phase * 5.0) * 0.15
        let raw = fundamental + harmonic3 + harmonic5
        let clipped = tanh(raw * 1.5)
        let detune = sin(phase2) * 0.25
        let sample = Float(clipped + detune) * amplitude

        buffer[0].mData?.assumingMemoryBound(to: Float.self)[frame] = sample
        phase += 2.0 * .pi * freq / sampleRate
        phase2 += 2.0 * .pi * (freq * 1.02) / sampleRate
        if phase > 2.0 * .pi { phase -= 2.0 * .pi }
        if phase2 > 2.0 * .pi { phase2 -= 2.0 * .pi }
        time += 1.0 / sampleRate
      }
      return noErr
    }
  }
}
