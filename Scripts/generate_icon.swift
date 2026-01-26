#!/usr/bin/env swift

import AppKit
import Foundation

// MARK: - Icon Drawing

func drawIcon(size: CGFloat) -> NSImage {
  let image = NSImage(size: NSSize(width: size, height: size))
  image.lockFocus()

  guard let ctx = NSGraphicsContext.current?.cgContext else {
    image.unlockFocus()
    return image
  }

  let rect = CGRect(x: 0, y: 0, width: size, height: size)
  drawBackground(ctx: ctx, rect: rect)
  drawLaptop(ctx: ctx, rect: rect)
  drawGuardEye(ctx: ctx, rect: rect)

  image.unlockFocus()
  return image
}

func drawBackground(ctx: CGContext, rect: CGRect) {
  let s = rect.width
  // macOS-style continuous rounded rect (superellipse approximation)
  let cornerRadius = s * 0.2237
  let path = CGPath(roundedRect: rect.insetBy(dx: s * 0.01, dy: s * 0.01),
                     cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                     transform: nil)

  // Dark gradient background
  ctx.saveGState()
  ctx.addPath(path)
  ctx.clip()

  let colors = [
    CGColor(red: 0.10, green: 0.10, blue: 0.18, alpha: 1.0),  // #1a1a2e
    CGColor(red: 0.086, green: 0.13, blue: 0.24, alpha: 1.0)   // #16213e
  ]
  let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: colors as CFArray,
                             locations: [0.0, 1.0])!
  ctx.drawLinearGradient(gradient,
                          start: CGPoint(x: s * 0.5, y: s),
                          end: CGPoint(x: s * 0.5, y: 0),
                          options: [])
  ctx.restoreGState()
}

func drawLaptop(ctx: CGContext, rect: CGRect) {
  let s = rect.width

  // Laptop base (bottom portion)
  let baseW = s * 0.56
  let baseH = s * 0.06
  let baseX = (s - baseW) / 2
  let baseY = s * 0.305

  ctx.saveGState()
  let basePath = CGPath(roundedRect: CGRect(x: baseX, y: baseY, width: baseW, height: baseH),
                         cornerWidth: baseH * 0.4, cornerHeight: baseH * 0.4,
                         transform: nil)
  ctx.setFillColor(CGColor(red: 0.70, green: 0.70, blue: 0.72, alpha: 1.0))
  ctx.addPath(basePath)
  ctx.fillPath()
  ctx.restoreGState()

  // Laptop screen (lid)
  let screenW = s * 0.46
  let screenH = s * 0.32
  let screenX = (s - screenW) / 2
  let screenY = baseY + baseH + s * 0.01
  let screenCorner = s * 0.02

  ctx.saveGState()
  let screenPath = CGPath(roundedRect: CGRect(x: screenX, y: screenY, width: screenW, height: screenH),
                           cornerWidth: screenCorner, cornerHeight: screenCorner,
                           transform: nil)
  ctx.setFillColor(CGColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 1.0))
  ctx.addPath(screenPath)
  ctx.fillPath()

  // Inner screen (dark)
  let innerMargin = s * 0.02
  let innerPath = CGPath(roundedRect: CGRect(x: screenX + innerMargin,
                                              y: screenY + innerMargin,
                                              width: screenW - innerMargin * 2,
                                              height: screenH - innerMargin * 2),
                          cornerWidth: screenCorner * 0.5, cornerHeight: screenCorner * 0.5,
                          transform: nil)
  ctx.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.16, alpha: 1.0))
  ctx.addPath(innerPath)
  ctx.fillPath()
  ctx.restoreGState()
}

func drawGuardEye(ctx: CGContext, rect: CGRect) {
  let s = rect.width
  let centerX = s * 0.5

  // Position eye at center of the inner screen
  let centerY = s * 0.535

  // Clip glow to inner screen area so it doesn't bleed outside the display
  let screenW = s * 0.46
  let screenH = s * 0.32
  let screenX = (s - screenW) / 2
  let screenY = s * 0.305 + s * 0.06 + s * 0.01
  let innerMargin = s * 0.02
  let innerRect = CGRect(x: screenX + innerMargin,
                          y: screenY + innerMargin,
                          width: screenW - innerMargin * 2,
                          height: screenH - innerMargin * 2)
  let innerCorner = s * 0.01

  // Subtle radial glow behind the eye (clipped to screen)
  ctx.saveGState()
  let innerClip = CGPath(roundedRect: innerRect,
                          cornerWidth: innerCorner, cornerHeight: innerCorner,
                          transform: nil)
  ctx.addPath(innerClip)
  ctx.clip()
  let glowColors = [
    CGColor(red: 1.0, green: 0.27, blue: 0.0, alpha: 0.30),
    CGColor(red: 1.0, green: 0.27, blue: 0.0, alpha: 0.0)
  ]
  let glowGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: glowColors as CFArray,
                                 locations: [0.0, 1.0])!
  ctx.drawRadialGradient(glowGradient,
                          startCenter: CGPoint(x: centerX, y: centerY),
                          startRadius: 0,
                          endCenter: CGPoint(x: centerX, y: centerY),
                          endRadius: s * 0.20,
                          options: [])
  ctx.restoreGState()

  // Eye shape — sized to fit within screen
  let eyeW = s * 0.34
  let eyeH = s * 0.12
  let eyePath = CGMutablePath()

  let leftX = centerX - eyeW / 2
  let rightX = centerX + eyeW / 2

  // Top arc
  eyePath.move(to: CGPoint(x: leftX, y: centerY))
  eyePath.addCurve(to: CGPoint(x: rightX, y: centerY),
                   control1: CGPoint(x: leftX + eyeW * 0.25, y: centerY + eyeH),
                   control2: CGPoint(x: rightX - eyeW * 0.25, y: centerY + eyeH))
  // Bottom arc
  eyePath.addCurve(to: CGPoint(x: leftX, y: centerY),
                   control1: CGPoint(x: rightX - eyeW * 0.25, y: centerY - eyeH),
                   control2: CGPoint(x: leftX + eyeW * 0.25, y: centerY - eyeH))
  eyePath.closeSubpath()

  // Fill eye with red-to-orange gradient
  ctx.saveGState()
  ctx.addPath(eyePath)
  ctx.clip()

  let eyeColors = [
    CGColor(red: 1.0, green: 0.27, blue: 0.27, alpha: 1.0),   // #ff4444
    CGColor(red: 1.0, green: 0.53, blue: 0.0, alpha: 1.0)      // #ff8800
  ]
  let eyeGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                colors: eyeColors as CFArray,
                                locations: [0.0, 1.0])!
  ctx.drawLinearGradient(eyeGradient,
                          start: CGPoint(x: leftX, y: centerY),
                          end: CGPoint(x: rightX, y: centerY),
                          options: [])
  ctx.restoreGState()

  // Eye outline
  ctx.saveGState()
  ctx.addPath(eyePath)
  ctx.setStrokeColor(CGColor(red: 1.0, green: 0.35, blue: 0.15, alpha: 0.6))
  ctx.setLineWidth(s * 0.008)
  ctx.strokePath()
  ctx.restoreGState()

  // Iris (circle)
  let irisR = s * 0.05
  let irisRect = CGRect(x: centerX - irisR, y: centerY - irisR,
                         width: irisR * 2, height: irisR * 2)
  ctx.saveGState()
  ctx.setFillColor(CGColor(red: 0.15, green: 0.05, blue: 0.05, alpha: 1.0))
  ctx.fillEllipse(in: irisRect)
  ctx.restoreGState()

  // Pupil (smaller circle)
  let pupilR = s * 0.025
  let pupilRect = CGRect(x: centerX - pupilR, y: centerY - pupilR,
                          width: pupilR * 2, height: pupilR * 2)
  ctx.saveGState()
  ctx.setFillColor(CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0))
  ctx.fillEllipse(in: pupilRect)
  ctx.restoreGState()

  // Highlight (small bright spot)
  let hlR = s * 0.01
  let hlRect = CGRect(x: centerX + pupilR * 0.4 - hlR,
                       y: centerY + pupilR * 0.4 - hlR,
                       width: hlR * 2, height: hlR * 2)
  ctx.saveGState()
  ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.8))
  ctx.fillEllipse(in: hlRect)
  ctx.restoreGState()
}

// MARK: - ICNS Generation

struct IconSize {
  let name: String
  let pixels: Int
}

let iconSizes: [IconSize] = [
  IconSize(name: "icon_16x16.png", pixels: 16),
  IconSize(name: "icon_16x16@2x.png", pixels: 32),
  IconSize(name: "icon_32x32.png", pixels: 32),
  IconSize(name: "icon_32x32@2x.png", pixels: 64),
  IconSize(name: "icon_128x128.png", pixels: 128),
  IconSize(name: "icon_128x128@2x.png", pixels: 256),
  IconSize(name: "icon_256x256.png", pixels: 256),
  IconSize(name: "icon_256x256@2x.png", pixels: 512),
  IconSize(name: "icon_512x512.png", pixels: 512),
  IconSize(name: "icon_512x512@2x.png", pixels: 1024),
]

func generateICNS() {
  let scriptDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
  let projectDir = scriptDir.deletingLastPathComponent()
  let resourcesDir = projectDir.appendingPathComponent("Resources")
  let iconsetDir = FileManager.default.temporaryDirectory.appendingPathComponent("LidGuard.iconset")

  // Clean up and create iconset directory
  try? FileManager.default.removeItem(at: iconsetDir)
  try! FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
  try? FileManager.default.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

  // Generate each size
  for iconSize in iconSizes {
    let size = CGFloat(iconSize.pixels)
    let image = drawIcon(size: size)

    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
      print("Failed to generate \(iconSize.name)")
      continue
    }

    let filePath = iconsetDir.appendingPathComponent(iconSize.name)
    try! pngData.write(to: filePath)
    print("Generated \(iconSize.name) (\(iconSize.pixels)x\(iconSize.pixels))")
  }

  // Convert to .icns using iconutil
  let outputPath = resourcesDir.appendingPathComponent("AppIcon.icns")
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
  process.arguments = ["-c", "icns", "-o", outputPath.path, iconsetDir.path]

  do {
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus == 0 {
      print("Created \(outputPath.path)")
    } else {
      print("iconutil failed with status \(process.terminationStatus)")
    }
  } catch {
    print("Failed to run iconutil: \(error)")
  }

  // Cleanup
  try? FileManager.default.removeItem(at: iconsetDir)
}

// MARK: - Main

generateICNS()
