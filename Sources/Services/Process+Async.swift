import Foundation

extension Process {
  /// Launches the process and suspends until it exits, without blocking a
  /// thread the way `waitUntilExit()` does. Resumes exactly once: via the
  /// termination handler on a clean launch, or via the thrown launch error.
  /// Inspect `terminationStatus` after the call returns.
  func runToCompletion() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      terminationHandler = { _ in continuation.resume() }
      do {
        try run()
      } catch {
        terminationHandler = nil
        continuation.resume(throwing: error)
      }
    }
  }
}
