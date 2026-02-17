import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {
  @Binding var keyCode: Int
  @Binding var modifiers: UInt

  func makeNSView(context: Context) -> ShortcutRecorderNSView {
    let view = ShortcutRecorderNSView()
    view.keyCode = keyCode
    view.modifiers = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
    view.onShortcutChanged = { newKeyCode, newModifiers in
      keyCode = newKeyCode
      modifiers = UInt(newModifiers.rawValue)
    }
    return view
  }

  func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
    nsView.keyCode = keyCode
    nsView.modifiers = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
    nsView.needsDisplay = true
  }
}

final class ShortcutRecorderNSView: NSView {
  var keyCode: Int = -1
  var modifiers: NSEvent.ModifierFlags = []
  var onShortcutChanged: ((Int, NSEvent.ModifierFlags) -> Void)?

  private var isRecording = false

  override var acceptsFirstResponder: Bool { true }

  override var intrinsicContentSize: NSSize {
    NSSize(width: 160, height: 24)
  }

  override func draw(_ dirtyRect: NSRect) {
    let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
    let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)

    if isRecording {
      NSColor.controlAccentColor.withAlphaComponent(0.1).setFill()
    } else {
      NSColor.controlBackgroundColor.setFill()
    }
    path.fill()

    NSColor.separatorColor.setStroke()
    path.lineWidth = 1
    path.stroke()

    let text: String
    if isRecording {
      text = "Press shortcut..."
    } else if keyCode >= 0 && modifiers.rawValue != 0 {
      text = shortcutDisplayString(keyCode: keyCode, modifiers: modifiers)
    } else {
      text = "Click to set"
    }

    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 13),
      .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor,
    ]
    let str = NSAttributedString(string: text, attributes: attrs)
    let size = str.size()
    let origin = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
    str.draw(at: origin)
  }

  override func mouseDown(with event: NSEvent) {
    isRecording = true
    window?.makeFirstResponder(self)
    needsDisplay = true
  }

  override func keyDown(with event: NSEvent) {
    guard isRecording else { return }

    if event.keyCode == 53 { // Escape
      isRecording = false
      needsDisplay = true
      return
    }

    let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
    guard !mods.isEmpty else { return }

    keyCode = Int(event.keyCode)
    modifiers = mods
    isRecording = false
    needsDisplay = true
    onShortcutChanged?(keyCode, modifiers)
  }

  override func resignFirstResponder() -> Bool {
    isRecording = false
    needsDisplay = true
    return super.resignFirstResponder()
  }
}

func shortcutDisplayString(keyCode: Int, modifiers: NSEvent.ModifierFlags) -> String {
  var parts = ""
  if modifiers.contains(.control) { parts += "\u{2303}" }
  if modifiers.contains(.option) { parts += "\u{2325}" }
  if modifiers.contains(.shift) { parts += "\u{21E7}" }
  if modifiers.contains(.command) { parts += "\u{2318}" }
  parts += keyCodeToString(UInt16(keyCode))
  return parts
}

private func keyCodeToString(_ keyCode: UInt16) -> String {
  let map: [UInt16: String] = [
    0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
    8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
    16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
    23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
    30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
    38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
    45: "N", 46: "M", 47: ".",
    36: "\u{21A9}", // Return
    48: "\u{21E5}", // Tab
    49: "\u{2423}", // Space
    51: "\u{232B}", // Delete
    53: "\u{238B}", // Escape
    96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
    101: "F9", 103: "F11", 105: "F13", 107: "F14",
    109: "F10", 111: "F12", 113: "F15",
    118: "F4", 119: "F2", 120: "F1", 122: "F16",
    123: "\u{2190}", 124: "\u{2192}", 125: "\u{2193}", 126: "\u{2191}", // Arrows
  ]
  return map[keyCode] ?? "Key\(keyCode)"
}
