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

  private var session: AVCaptureSession?
  private var output: AVCapturePhotoOutput?
  private var pending: (@Sendable (Data?) -> Void)?

  func authorizationStatus() -> AVAuthorizationStatus {
    AVCaptureDevice.authorizationStatus(for: .video)
  }

  func requestAccess(_ completion: @escaping @Sendable (Bool) -> Void) {
    AVCaptureDevice.requestAccess(for: .video) { granted in completion(granted) }
  }

  func capturePhoto(_ completion: @escaping @Sendable (Data?) -> Void) {
    // Best-effort, one shot at a time: if a capture is already in flight, skip this one
    // rather than clobber the in-flight session/completion.
    guard pending == nil else { completion(nil); return }
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

    session.startRunning()
    // Brief warm-up so the sensor exposes before the shot.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
      MainActor.assumeIsolated {
        guard let self, let output = self.output else { return }
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
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
}

extension CameraCaptureService: AVCapturePhotoCaptureDelegate {
  nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                               didFinishProcessingPhoto photo: AVCapturePhoto,
                               error: Error?) {
    let data = photo.fileDataRepresentation()
    DispatchQueue.main.async {
      MainActor.assumeIsolated {
        CameraCaptureService.shared.finish(error == nil ? data : nil)
      }
    }
  }
}
