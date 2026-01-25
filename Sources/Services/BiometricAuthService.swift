import Foundation
import LocalAuthentication

protocol AuthenticationService {
  func authenticate(reason: String, completion: @escaping (Bool) -> Void)
}

final class BiometricAuthService: AuthenticationService {
  func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
    let context = LAContext()

    // Use deviceOwnerAuthentication to allow both Touch ID and password fallback
    context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
      DispatchQueue.main.async {
        completion(success)
      }
    }
  }
}
