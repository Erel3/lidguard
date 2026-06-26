import Foundation

/// Builds one Telegram HTML message summarizing a batch of offline tracking updates,
/// so a reconnect after an offline gap sends a single message instead of replaying each.
enum CoalesceSummary {
  static func build(from snapshots: [DeviceSnapshot]) -> String {
    guard let first = snapshots.first, let last = snapshots.last else { return "" }

    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd HH:mm:ss"

    var lines: [String] = []
    let noun = snapshots.count == 1 ? "update" : "updates"
    lines.append("📦 <b>OFFLINE SUMMARY</b> — \(snapshots.count) \(noun)")
    lines.append("🕐 <b>Span:</b> \(df.string(from: first.timestamp)) → \(df.string(from: last.timestamp))")

    if let lat = last.latitude, let lng = last.longitude {
      lines.append("📍 <b>Latest:</b> \(lat), \(lng)")
      lines.append("🗺 <b>Maps:</b> https://maps.google.com/?q=\(lat),\(lng)")
      if let acc = last.accuracy { lines.append("🎯 <b>Accuracy:</b> \(Int(acc))m") }
    } else {
      lines.append("📍 <b>Latest:</b> unavailable")
    }

    if let startB = first.batteryLevel, let endB = last.batteryLevel {
      let status = last.isCharging == true ? "charging" : "discharging"
      lines.append("🔋 <b>Battery:</b> \(startB)% → \(endB)% (\(status))")
    } else if let endB = last.batteryLevel {
      lines.append("🔋 <b>Battery:</b> \(endB)%")
    }

    if let endIP = last.publicIP {
      let changed = first.publicIP != nil && first.publicIP != last.publicIP
      lines.append("🌐 <b>Public IP:</b> \(htmlEscape(endIP))\(changed ? " (changed)" : "")")
    }
    if let endWifi = last.wifiName {
      let changed = first.wifiName != nil && first.wifiName != last.wifiName
      lines.append("📶 <b>WiFi:</b> \(htmlEscape(endWifi))\(changed ? " (changed)" : "")")
    }

    return lines.joined(separator: "\n")
  }

  private static func htmlEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
  }
}
