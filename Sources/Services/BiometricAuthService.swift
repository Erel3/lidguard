import Foundation
import LocalAuthentication

protocol AuthenticationService {
  func authenticate(reason: String, completion: @escaping (Bool) -> Void)
}

final class BiometricAuthService: AuthenticationService {
  func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
    let context = LAContext()
    var error: NSError?

    let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
      ? .deviceOwnerAuthenticationWithBiometrics
      : .deviceOwnerAuthentication

    context.evaluatePolicy(policy, localizedReason: reason) { success, authError in
      if let authError = authError {
        print("[BiometricAuthService] Error: \(authError.localizedDescription)")
      }
      DispatchQueue.main.async {
        completion(success)
      }
    }
  }
}
