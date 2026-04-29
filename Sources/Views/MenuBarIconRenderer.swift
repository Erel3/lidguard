import AppKit

enum MenuBarIconStyle {
  case eyeOpen                 // enabled / monitoring
  case eyeOpenBluetooth        // auto-armed via bluetooth (yellow)
  case eyeHalfClosedBluetooth  // disabled but BT monitoring active (yellow half-closed)
  case eyeClosed               // disabled
  case eyeAlert                // theft mode — eye + exclamation
}

enum MenuBarIconRenderer {
  private struct EyeGeometry {
    let centerY: CGFloat
    let width: CGFloat
    let height: CGFloat
    let centerX: CGFloat
    var leftX: CGFloat { centerX - width / 2 }
    var rightX: CGFloat { centerX + width / 2 }
  }

  static func laptopIcon(_ style: MenuBarIconStyle) -> NSImage {
    let size: CGFloat = 18
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    if let ctx = NSGraphicsContext.current?.cgContext {
      ctx.setStrokeColor(.black)
      ctx.setFillColor(.black)
      ctx.setLineWidth(size * 0.065)
      ctx.setLineCap(.round)
      ctx.setLineJoin(.round)
      drawLaptopBody(ctx: ctx, s: size, cx: size * 0.5)
      if style == .eyeClosed {
        let eye = defaultEye(size: size)
        drawEyeShape(ctx: ctx, s: size, style: style, eye: eye)
      }
    }
    image.unlockFocus()
    image.isTemplate = true
    return image
  }

  static func eyeImage(_ style: MenuBarIconStyle) -> NSImage {
    let size: CGFloat = 18
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    if let ctx = NSGraphicsContext.current?.cgContext {
      let color: CGColor
      switch style {
      case .eyeOpen, .eyeOpenBluetooth:
        color = CGColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1.0)
      case .eyeHalfClosedBluetooth:
        color = CGColor(red: 0.95, green: 0.75, blue: 0.1, alpha: 1.0)
      case .eyeAlert:
        color = CGColor(red: 0.9, green: 0.2, blue: 0.15, alpha: 1.0)
      case .eyeClosed:
        color = .black
      }
      ctx.setStrokeColor(color)
      ctx.setFillColor(color)
      ctx.setLineWidth(size * 0.065)
      ctx.setLineCap(.round)
      ctx.setLineJoin(.round)
      let eye = defaultEye(size: size)
      drawEyeShape(ctx: ctx, s: size, style: style, eye: eye)
    }
    image.unlockFocus()
    image.isTemplate = false
    return image
  }

  private static func defaultEye(size: CGFloat) -> EyeGeometry {
    let screenH = size * 0.42
    let screenY = size * 0.38
    let eyeCY = screenY + screenH * 0.5
    let eyeW = size * 0.36
    let eyeH = size * 0.14
    let cx = size * 0.5
    return EyeGeometry(centerY: eyeCY, width: eyeW, height: eyeH, centerX: cx)
  }

  private static func drawLaptopBody(ctx: CGContext, s: CGFloat, cx: CGFloat) {
    let screenW = s * 0.72
    let screenH = s * 0.42
    let screenY = s * 0.38
    let screenCorner = s * 0.04
    let screenPath = CGPath(roundedRect: CGRect(x: cx - screenW / 2, y: screenY,
                                                 width: screenW, height: screenH),
                             cornerWidth: screenCorner, cornerHeight: screenCorner,
                             transform: nil)
    ctx.addPath(screenPath)
    ctx.strokePath()

    let hingeW = screenW * 0.5
    let hingeH = s * 0.035
    ctx.fill([CGRect(x: cx - hingeW / 2, y: screenY - hingeH, width: hingeW, height: hingeH)])

    let baseTopW = screenW + s * 0.06
    let baseBotW = screenW + s * 0.18
    let baseH = s * 0.09
    let baseTopY = screenY - hingeH - s * 0.01
    let baseBotY = baseTopY - baseH
    let cr = s * 0.02

    let base = CGMutablePath()
    base.move(to: CGPoint(x: cx - baseTopW / 2, y: baseTopY))
    base.addLine(to: CGPoint(x: cx + baseTopW / 2, y: baseTopY))
    base.addLine(to: CGPoint(x: cx + baseBotW / 2 - cr, y: baseBotY + cr))
    base.addQuadCurve(to: CGPoint(x: cx + baseBotW / 2, y: baseBotY),
                      control: CGPoint(x: cx + baseBotW / 2, y: baseBotY + cr))
    base.addLine(to: CGPoint(x: cx - baseBotW / 2, y: baseBotY))
    base.addQuadCurve(to: CGPoint(x: cx - baseBotW / 2 + cr, y: baseBotY + cr),
                      control: CGPoint(x: cx - baseBotW / 2, y: baseBotY + cr))
    base.closeSubpath()
    ctx.addPath(base)
    ctx.fillPath()
  }

  private static func drawEyeShape(ctx: CGContext, s: CGFloat, style: MenuBarIconStyle, eye: EyeGeometry) {
    let eyeCY = eye.centerY, eyeW = eye.width, eyeH = eye.height
    let leftX = eye.leftX, rightX = eye.rightX, cx = eye.centerX
    switch style {
    case .eyeOpen, .eyeAlert:
      let path = CGMutablePath()
      path.move(to: CGPoint(x: leftX, y: eyeCY))
      path.addCurve(to: CGPoint(x: rightX, y: eyeCY),
                    control1: CGPoint(x: leftX + eyeW * 0.25, y: eyeCY + eyeH),
                    control2: CGPoint(x: rightX - eyeW * 0.25, y: eyeCY + eyeH))
      path.addCurve(to: CGPoint(x: leftX, y: eyeCY),
                    control1: CGPoint(x: rightX - eyeW * 0.25, y: eyeCY - eyeH),
                    control2: CGPoint(x: leftX + eyeW * 0.25, y: eyeCY - eyeH))
      path.closeSubpath()

      ctx.addPath(path)
      ctx.strokePath()

      let irisR = s * 0.08
      ctx.fillEllipse(in: CGRect(x: cx - irisR, y: eyeCY - irisR,
                                  width: irisR * 2, height: irisR * 2))

    case .eyeOpenBluetooth, .eyeHalfClosedBluetooth:
      let halfPath = CGMutablePath()
      halfPath.move(to: CGPoint(x: leftX, y: eyeCY))
      halfPath.addCurve(to: CGPoint(x: rightX, y: eyeCY),
                        control1: CGPoint(x: leftX + eyeW * 0.25, y: eyeCY - eyeH),
                        control2: CGPoint(x: rightX - eyeW * 0.25, y: eyeCY - eyeH))
      let halfH = eyeH * 0.4
      halfPath.addCurve(to: CGPoint(x: leftX, y: eyeCY),
                        control1: CGPoint(x: rightX - eyeW * 0.25, y: eyeCY + halfH),
                        control2: CGPoint(x: leftX + eyeW * 0.25, y: eyeCY + halfH))
      halfPath.closeSubpath()

      ctx.addPath(halfPath)
      ctx.strokePath()

      let irisR = s * 0.05
      ctx.fillEllipse(in: CGRect(x: cx - irisR, y: eyeCY - irisR * 1.5,
                                  width: irisR * 2, height: irisR * 2))

    case .eyeClosed:
      let closedCY = eyeCY + s * 0.06
      let closedLeftX = cx - eyeW / 2
      let closedRightX = cx + eyeW / 2

      let path = CGMutablePath()
      path.move(to: CGPoint(x: closedLeftX, y: closedCY))
      path.addCurve(to: CGPoint(x: closedRightX, y: closedCY),
                    control1: CGPoint(x: closedLeftX + eyeW * 0.25, y: closedCY - eyeH),
                    control2: CGPoint(x: closedRightX - eyeW * 0.25, y: closedCY - eyeH))

      ctx.addPath(path)
      ctx.strokePath()

      let lashLen = s * 0.06
      for t: CGFloat in [0.25, 0.5, 0.75] {
        let x = closedLeftX + eyeW * t
        let yOff = eyeH * (1.0 - 4.0 * (t - 0.5) * (t - 0.5))
        let y = closedCY - yOff
        ctx.move(to: CGPoint(x: x, y: y))
        ctx.addLine(to: CGPoint(x: x, y: y - lashLen))
      }
      ctx.strokePath()
    }
  }
}
