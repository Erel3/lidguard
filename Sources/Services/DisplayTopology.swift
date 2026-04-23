import CoreGraphics

enum DisplayTopology {
  /// True if an external display is attached (any active display whose
  /// CGDisplayIsBuiltin returns 0). Clamshell at a dock is normal use and
  /// should not trigger theft mode.
  static func hasExternalDisplay() -> Bool {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return false }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return false }
    for id in ids where CGDisplayIsBuiltin(id) == 0 {
      return true
    }
    return false
  }
}
