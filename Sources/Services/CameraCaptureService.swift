import AVFoundation
import Foundation

/// Pure cadence rule: capture on every Nth *tracking* update. `updateCount` counts all
/// updates including the initial one (sent at activation, updateCount == 1, already covered
/// by capture-on-activation), so `(updateCount - 1)` is the tracking-tick index for cadence.
enum PhotoCadence {
  static func shouldCaptureOnUpdate(updateCount: Int, everyN: Int) -> Bool {
    guard everyN > 0, updateCount > 1 else { return false }
    return (updateCount - 1) % everyN == 0
  }
}

@MainActor
protocol CameraCapturing {
  func authorizationStatus() -> AVAuthorizationStatus
  func requestAccess(_ completion: @escaping @Sendable (Bool) -> Void)
  func capturePhoto(_ completion: @escaping @Sendable (Data?) -> Void)
  func captureVideo(_ completion: @escaping @Sendable (URL?) -> Void)
}

/// Captures a single JPEG from the front camera, tearing the session down after each
/// shot (frees the camera indicator between shots, lower battery). Failures return nil;
/// callers must treat photo capture as best-effort and never block tracking on it.
@MainActor
final class CameraCaptureService: NSObject, CameraCapturing {
  static let shared = CameraCaptureService()

  // Singleton-only: the nonisolated capture delegate routes back through `.shared`,
  // so a separately-constructed instance would deliver its result to the wrong object.
  private override init() { super.init() }

  static let videoDuration: TimeInterval = 5

  private var session: AVCaptureSession?
  private var output: AVCapturePhotoOutput?
  private var pending: (@Sendable (Data?) -> Void)?
  // Distinguishes capture attempts so a stale warm-up/watchdog can't act on a newer capture.
  private var captureGeneration = 0

  private var movieOutput: AVCaptureMovieFileOutput?
  private var videoPending: (@Sendable (URL?) -> Void)?

  func authorizationStatus() -> AVAuthorizationStatus {
    AVCaptureDevice.authorizationStatus(for: .video)
  }

  func requestAccess(_ completion: @escaping @Sendable (Bool) -> Void) {
    AVCaptureDevice.requestAccess(for: .video) { granted in completion(granted) }
  }

  func capturePhoto(_ completion: @escaping @Sendable (Data?) -> Void) {
    // Best-effort, one shot at a time: if a capture is already in flight, skip this one
    // rather than clobber the in-flight session/completion.
    guard pending == nil, videoPending == nil else { completion(nil); return }
    guard authorizationStatus() == .authorized else { completion(nil); return }
    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
          let input = try? AVCaptureDeviceInput(device: device) else { completion(nil); return }

    let session = AVCaptureSession()
    session.sessionPreset = .photo
    guard session.canAddInput(input) else { completion(nil); return }
    session.addInput(input)

    let output = AVCapturePhotoOutput()
    guard session.canAddOutput(output) else { completion(nil); return }
    session.addOutput(output)

    self.session = session
    self.output = output
    self.pending = completion
    captureGeneration &+= 1
    let gen = captureGeneration

    session.startRunning()
    // Brief warm-up so the sensor exposes before the shot.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.captureGeneration == gen, let output = self.output else { return }
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
      }
    }
    // Watchdog: if the delegate never fires (camera contention / runtime error), tear the
    // session down and fail this capture so the camera frees and future captures aren't blocked.
    DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.captureGeneration == gen, self.pending != nil else { return }
        ActivityLog.logAsync(.theft, "Thief photo capture timed out")
        self.finish(nil)
      }
    }
  }

  private func finish(_ data: Data?) {
    session?.stopRunning()
    session = nil
    output = nil
    let cb = pending
    pending = nil
    cb?(data)
  }

  func captureVideo(_ completion: @escaping @Sendable (URL?) -> Void) {
    guard pending == nil, videoPending == nil else { completion(nil); return }
    guard authorizationStatus() == .authorized else { completion(nil); return }
    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
          let input = try? AVCaptureDeviceInput(device: device) else { completion(nil); return }

    let session = AVCaptureSession()
    session.sessionPreset = .high
    guard session.canAddInput(input) else { completion(nil); return }
    session.addInput(input)            // video only — no audio input

    let movieOutput = AVCaptureMovieFileOutput()
    guard session.canAddOutput(movieOutput) else { completion(nil); return }
    session.addOutput(movieOutput)

    self.session = session
    self.movieOutput = movieOutput
    self.videoPending = completion
    captureGeneration &+= 1
    let gen = captureGeneration

    session.startRunning()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.captureGeneration == gen, let movieOutput = self.movieOutput else { return }
        movieOutput.startRecording(to: url, recordingDelegate: self)
        DispatchQueue.main.asyncAfter(deadline: .now() + CameraCaptureService.videoDuration) { [weak self] in
          MainActor.assumeIsolated {
            guard let self, self.captureGeneration == gen,
                  let movieOutput = self.movieOutput, movieOutput.isRecording else { return }
            movieOutput.stopRecording()   // -> fileOutput(_:didFinishRecordingTo:...)
          }
        }
      }
    }
    // Watchdog: if recording never completes, tear down + fail so the camera frees.
    DispatchQueue.main.asyncAfter(deadline: .now() + CameraCaptureService.videoDuration + 4.0) { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.captureGeneration == gen, self.videoPending != nil else { return }
        ActivityLog.logAsync(.theft, "Thief video capture timed out")
        self.finishVideo(nil)
      }
    }
  }

  private func finishVideo(_ url: URL?) {
    session?.stopRunning()
    session = nil
    movieOutput = nil
    let cb = videoPending
    videoPending = nil
    if cb == nil, let url { try? FileManager.default.removeItem(at: url) }  // no consumer (watchdog fired) — clean up
    cb?(url)
  }
}

extension CameraCaptureService: AVCapturePhotoCaptureDelegate {
  nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                               didFinishProcessingPhoto photo: AVCapturePhoto,
                               error: Error?) {
    let data = photo.fileDataRepresentation()
    let outputID = ObjectIdentifier(output)
    DispatchQueue.main.async {
      MainActor.assumeIsolated {
        let svc = CameraCaptureService.shared
        // Ignore a late delegate whose capture was already finished/superseded
        // (e.g. the watchdog fired and a newer capture started). Otherwise this
        // would tear down the newer session and deliver stale bytes to it.
        guard let current = svc.output, ObjectIdentifier(current) == outputID else { return }
        svc.finish(error == nil ? data : nil)
      }
    }
  }
}

extension CameraCaptureService: AVCaptureFileOutputRecordingDelegate {
  nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                              didFinishRecordingTo outputFileURL: URL,
                              from connections: [AVCaptureConnection],
                              error: Error?) {
    // AVFoundation can report a benign "error" (e.g. stopped at max duration) while the
    // file is still usable — treat AVErrorRecordingSuccessfullyFinishedKey == true as success.
    let succeeded = error == nil
      || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) == true
    if !succeeded {
      try? FileManager.default.removeItem(at: outputFileURL)   // drop the partial recording
    }
    let outputID = ObjectIdentifier(output)
    DispatchQueue.main.async {
      MainActor.assumeIsolated {
        let svc = CameraCaptureService.shared
        // Ignore a late delegate for a superseded capture (see photoOutput).
        guard let current = svc.movieOutput, ObjectIdentifier(current) == outputID else {
          if succeeded { try? FileManager.default.removeItem(at: outputFileURL) }
          return
        }
        svc.finishVideo(succeeded ? outputFileURL : nil)
      }
    }
  }
}
