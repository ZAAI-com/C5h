import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import AppKit

// MARK: - Output

let outRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Docs/Icons", isDirectory: true)
try? FileManager.default.createDirectory(at: outRoot, withIntermediateDirectories: true)

let canvas: CGFloat = 1024
let cornerRadius: CGFloat = 224

let π: CGFloat = .pi
let τ: CGFloat = (.pi as CGFloat) * 2

// MARK: - Helpers

func makeContext(size: CGFloat = canvas) -> CGContext {
    CGContext(
        data: nil,
        width: Int(size),
        height: Int(size),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

func writePNG(_ ctx: CGContext, to url: URL) throws {
    guard let image = ctx.makeImage() else {
        throw NSError(domain: "IconForge", code: 1, userInfo: [NSLocalizedDescriptionKey: "no image"])
    }
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "IconForge", code: 2, userInfo: [NSLocalizedDescriptionKey: "no destination"])
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "IconForge", code: 3, userInfo: [NSLocalizedDescriptionKey: "finalize failed"])
    }
}

func clip(_ ctx: CGContext, to rect: CGRect = .init(x: 0, y: 0, width: canvas, height: canvas)) {
    let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(path)
    ctx.clip()
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func gradient(colors: [CGColor], locations: [CGFloat] = []) -> CGGradient {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    if locations.isEmpty {
        return CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    }
    return CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

func paint(_ ctx: CGContext, linear gradient: CGGradient, from: CGPoint, to: CGPoint) {
    ctx.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func paint(_ ctx: CGContext, radial gradient: CGGradient, center: CGPoint, radius: CGFloat) {
    ctx.drawRadialGradient(
        gradient,
        startCenter: center, startRadius: 0,
        endCenter: center, endRadius: radius,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
}

func drawText(
    _ ctx: CGContext,
    _ string: String,
    at point: CGPoint,
    size: CGFloat,
    weight: NSFont.Weight = .bold,
    color: CGColor,
    design: NSFontDescriptor.SystemDesign = .rounded,
    align: CTTextAlignment = .center
) {
    let baseFont = NSFont.systemFont(ofSize: size, weight: weight)
    let descriptor = baseFont.fontDescriptor.withDesign(design) ?? baseFont.fontDescriptor
    let font = NSFont(descriptor: descriptor, size: size) ?? baseFont
    var alignSetting = align
    let setting = withUnsafePointer(to: &alignSetting) {
        CTParagraphStyleSetting(
            spec: .alignment,
            valueSize: MemoryLayout<CTTextAlignment>.size,
            value: UnsafeRawPointer($0)
        )
    }
    let paragraph = CTParagraphStyleCreate([setting], 1)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(cgColor: color) ?? .white,
        .paragraphStyle: paragraph
    ]
    let attributed = NSAttributedString(string: string, attributes: attributes)
    let line = CTLineCreateWithAttributedString(attributed)
    let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
    ctx.saveGState()
    ctx.textPosition = CGPoint(
        x: point.x - bounds.width / 2 - bounds.origin.x,
        y: point.y - bounds.height / 2 - bounds.origin.y
    )
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

// MARK: - Brand colors

let claude = rgb(217, 110, 64)
let claudeDeep = rgb(176, 76, 30)
let claudeBright = rgb(255, 142, 80)
let codex = rgb(38, 100, 235)
let codexDeep = rgb(20, 60, 165)
let codexBright = rgb(80, 140, 255)
let cream = rgb(245, 239, 230)
let creamLight = rgb(252, 248, 241)
let navy = rgb(15, 24, 48)
let navyDeep = rgb(8, 12, 28)
let white = rgb(255, 255, 255)
let nearBlack = rgb(20, 22, 30)

// MARK: - 1. Wedge Clock

func renderWedgeClock() throws {
    let ctx = makeContext()
    clip(ctx)

    // Warm orange gradient background
    paint(ctx,
          linear: gradient(colors: [claudeBright, claudeDeep]),
          from: CGPoint(x: 0, y: canvas),
          to: CGPoint(x: canvas, y: 0))

    // Subtle inner glow
    paint(ctx,
          radial: gradient(colors: [
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.18),
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)
          ]),
          center: CGPoint(x: canvas / 2, y: canvas * 0.62),
          radius: canvas * 0.55)

    // Clock face
    let center = CGPoint(x: canvas / 2, y: canvas / 2)
    let faceR: CGFloat = 380
    ctx.setFillColor(white)
    ctx.addArc(center: center, radius: faceR, startAngle: 0, endAngle: τ, clockwise: false)
    ctx.fillPath()

    // 5-hour wedge from 12 (top) sweeping clockwise to 5 (i.e. 5/12 of a turn)
    let wedgeR: CGFloat = 360
    ctx.setFillColor(rgb(255, 110, 50))
    ctx.move(to: center)
    ctx.addArc(
        center: center,
        radius: wedgeR,
        startAngle: -π / 2,
        endAngle: -π / 2 + (τ) * 5 / 12,
        clockwise: false
    )
    ctx.closePath()
    ctx.fillPath()

    // Hour ticks at 12, 3, 6, 9
    ctx.setFillColor(nearBlack)
    for hour in [0, 3, 6, 9] {
        let angle = -π / 2 + (τ) * CGFloat(hour) / 12
        let outer = CGPoint(x: center.x + cos(angle) * faceR * 0.92,
                            y: center.y + sin(angle) * faceR * 0.92)
        let inner = CGPoint(x: center.x + cos(angle) * faceR * 0.78,
                            y: center.y + sin(angle) * faceR * 0.78)
        ctx.setLineWidth(18)
        ctx.setLineCap(.round)
        ctx.setStrokeColor(nearBlack)
        ctx.move(to: inner)
        ctx.addLine(to: outer)
        ctx.strokePath()
    }

    // Hour hand (pointing at 5)
    let handAngle = -π / 2 + (τ) * 5 / 12
    ctx.setStrokeColor(nearBlack)
    ctx.setLineWidth(28)
    ctx.setLineCap(.round)
    ctx.move(to: center)
    ctx.addLine(to: CGPoint(x: center.x + cos(handAngle) * faceR * 0.62,
                            y: center.y + sin(handAngle) * faceR * 0.62))
    ctx.strokePath()

    // Minute hand pointing up
    ctx.setLineWidth(20)
    ctx.move(to: center)
    ctx.addLine(to: CGPoint(x: center.x, y: center.y + faceR * 0.78))
    ctx.strokePath()

    // Center hub
    ctx.setFillColor(nearBlack)
    ctx.addArc(center: center, radius: 36, startAngle: 0, endAngle: τ, clockwise: false)
    ctx.fillPath()
    ctx.setFillColor(claude)
    ctx.addArc(center: center, radius: 18, startAngle: 0, endAngle: τ, clockwise: false)
    ctx.fillPath()

    try writePNG(ctx, to: outRoot.appendingPathComponent("01-wedge-clock.png"))
    print("✓ 01-wedge-clock.png")
}

// MARK: - 2. Activity Rings

func renderActivityRings() throws {
    let ctx = makeContext()
    clip(ctx)

    // Dark navy radial gradient
    paint(ctx,
          radial: gradient(colors: [rgb(40, 56, 92), navyDeep]),
          center: CGPoint(x: canvas / 2, y: canvas / 2),
          radius: canvas * 0.7)

    let center = CGPoint(x: canvas / 2, y: canvas / 2)
    let stroke: CGFloat = 96

    func ring(radius: CGFloat, fraction: CGFloat, baseColor: CGColor, fillColor: CGColor) {
        // Track
        ctx.setLineWidth(stroke)
        ctx.setStrokeColor(baseColor)
        ctx.setLineCap(.round)
        ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: τ, clockwise: false)
        ctx.strokePath()
        // Filled portion (starting at 12 o'clock, going clockwise)
        ctx.setStrokeColor(fillColor)
        ctx.setLineWidth(stroke)
        ctx.setLineCap(.round)
        let start = -π / 2
        let end = start + τ * fraction
        ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        ctx.strokePath()
    }

    // Outer ring: Claude (5/24 ≈ 0.208)
    ring(
        radius: 360,
        fraction: 5.0 / 24.0,
        baseColor: rgb(217, 110, 64, 0.22),
        fillColor: claudeBright
    )
    // Inner ring: Codex
    ring(
        radius: 230,
        fraction: 5.0 / 24.0,
        baseColor: rgb(38, 100, 235, 0.22),
        fillColor: codexBright
    )

    // Subtle "5h" in middle
    drawText(ctx, "5h", at: CGPoint(x: center.x, y: center.y), size: 220, color: white)

    try writePNG(ctx, to: outRoot.appendingPathComponent("02-activity-rings.png"))
    print("✓ 02-activity-rings.png")
}

// MARK: - 3. Stacked Bars

func renderStackedBars() throws {
    let ctx = makeContext()
    clip(ctx)

    // Cream background
    ctx.setFillColor(cream)
    ctx.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))

    // Faint vertical hour gridlines
    ctx.setStrokeColor(rgb(180, 165, 140, 0.35))
    ctx.setLineWidth(2)
    for i in 1..<6 {
        let x = canvas / 6 * CGFloat(i)
        ctx.move(to: CGPoint(x: x, y: 140))
        ctx.addLine(to: CGPoint(x: x, y: canvas - 140))
        ctx.strokePath()
    }

    func lane(yCenter: CGFloat, plannedColor: CGColor, plannedBorder: CGColor, actualColor: CGColor, plannedX: CGFloat, plannedWidth: CGFloat, actualX: CGFloat, actualWidth: CGFloat) {
        // Planned (narrow, leading, translucent + bordered)
        let plannedRect = CGRect(x: plannedX, y: yCenter - 110, width: plannedWidth, height: 220)
        let p = CGPath(roundedRect: plannedRect, cornerWidth: 32, cornerHeight: 32, transform: nil)
        ctx.addPath(p)
        ctx.setFillColor(plannedColor)
        ctx.fillPath()
        ctx.addPath(p)
        ctx.setLineWidth(8)
        ctx.setStrokeColor(plannedBorder)
        ctx.strokePath()

        // Actual (wide, trailing, solid)
        let actualRect = CGRect(x: actualX, y: yCenter - 86, width: actualWidth, height: 172)
        let a = CGPath(roundedRect: actualRect, cornerWidth: 32, cornerHeight: 32, transform: nil)
        ctx.addPath(a)
        ctx.setFillColor(actualColor)
        ctx.fillPath()
    }

    // Top: Claude
    lane(
        yCenter: canvas * 0.68,
        plannedColor: rgb(217, 110, 64, 0.22),
        plannedBorder: claude,
        actualColor: claude,
        plannedX: 110,
        plannedWidth: 360,
        actualX: 280,
        actualWidth: 580
    )

    // Bottom: Codex
    lane(
        yCenter: canvas * 0.32,
        plannedColor: rgb(38, 100, 235, 0.22),
        plannedBorder: codex,
        actualColor: codex,
        plannedX: 200,
        plannedWidth: 320,
        actualX: 360,
        actualWidth: 540
    )

    try writePNG(ctx, to: outRoot.appendingPathComponent("03-stacked-bars.png"))
    print("✓ 03-stacked-bars.png")
}

// MARK: - 4. Numeral 5h

func renderNumeral5h() throws {
    let ctx = makeContext()
    clip(ctx)

    // Vertical Claude→Codex gradient
    paint(ctx,
          linear: gradient(colors: [
            rgb(232, 122, 70),
            rgb(174, 102, 152),
            rgb(58, 116, 220)
          ]),
          from: CGPoint(x: canvas * 0.3, y: canvas),
          to: CGPoint(x: canvas * 0.7, y: 0))

    // Soft top highlight
    paint(ctx,
          radial: gradient(colors: [
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22),
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)
          ]),
          center: CGPoint(x: canvas * 0.32, y: canvas * 0.85),
          radius: canvas * 0.55)

    // "5" centered
    drawText(ctx, "5",
             at: CGPoint(x: canvas * 0.42, y: canvas * 0.5),
             size: 740,
             weight: .black,
             color: white,
             design: .rounded)

    // small "h" baseline-aligned to bottom-right of 5
    drawText(ctx, "h",
             at: CGPoint(x: canvas * 0.78, y: canvas * 0.34),
             size: 320,
             weight: .heavy,
             color: white,
             design: .rounded)

    try writePNG(ctx, to: outRoot.appendingPathComponent("04-numeral-5h.png"))
    print("✓ 04-numeral-5h.png")
}

// MARK: - 5. Hourglass Split

func renderHourglassSplit() throws {
    let ctx = makeContext()
    clip(ctx)

    // Cream background with subtle radial
    ctx.setFillColor(creamLight)
    ctx.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))
    paint(ctx,
          radial: gradient(colors: [
            rgb(255, 230, 200, 0.5),
            rgb(255, 230, 200, 0)
          ]),
          center: CGPoint(x: canvas / 2, y: canvas * 0.55),
          radius: canvas * 0.5)

    // Hourglass silhouette: two triangles meeting at center
    // We'll use rounded triangles via CGPath
    let cx = canvas / 2
    let topY = canvas * 0.18
    let bottomY = canvas * 0.82
    let neckY = canvas * 0.50
    let halfWidth: CGFloat = 280
    let neckWidth: CGFloat = 60

    // Glass body — light translucent stroke
    let glassPath = CGMutablePath()
    glassPath.move(to: CGPoint(x: cx - halfWidth, y: topY))
    glassPath.addLine(to: CGPoint(x: cx + halfWidth, y: topY))
    glassPath.addLine(to: CGPoint(x: cx + neckWidth, y: neckY))
    glassPath.addLine(to: CGPoint(x: cx + halfWidth, y: bottomY))
    glassPath.addLine(to: CGPoint(x: cx - halfWidth, y: bottomY))
    glassPath.addLine(to: CGPoint(x: cx - neckWidth, y: neckY))
    glassPath.closeSubpath()

    ctx.addPath(glassPath)
    ctx.setFillColor(rgb(255, 255, 255, 0.85))
    ctx.fillPath()

    // Top sand (Claude orange) — most of upper half
    let topSandPath = CGMutablePath()
    topSandPath.move(to: CGPoint(x: cx - halfWidth + 30, y: topY + 20))
    topSandPath.addLine(to: CGPoint(x: cx + halfWidth - 30, y: topY + 20))
    topSandPath.addLine(to: CGPoint(x: cx + neckWidth + 8, y: neckY))
    topSandPath.addLine(to: CGPoint(x: cx - neckWidth - 8, y: neckY))
    topSandPath.closeSubpath()
    ctx.addPath(topSandPath)
    ctx.setFillColor(claude)
    ctx.fillPath()

    // Bottom sand (Codex blue) — small mound
    let bottomSandPath = CGMutablePath()
    let mound = halfWidth - 60
    bottomSandPath.move(to: CGPoint(x: cx - mound, y: bottomY - 20))
    bottomSandPath.addLine(to: CGPoint(x: cx + mound, y: bottomY - 20))
    bottomSandPath.addCurve(
        to: CGPoint(x: cx - mound, y: bottomY - 20),
        control1: CGPoint(x: cx + 100, y: bottomY - 250),
        control2: CGPoint(x: cx - 100, y: bottomY - 250)
    )
    bottomSandPath.closeSubpath()
    ctx.addPath(bottomSandPath)
    ctx.setFillColor(codex)
    ctx.fillPath()

    // Falling sand stream (gradient)
    let streamRect = CGRect(x: cx - 12, y: bottomY - 240, width: 24, height: 240)
    ctx.saveGState()
    ctx.clip(to: streamRect)
    paint(ctx,
          linear: gradient(colors: [claude, codex]),
          from: CGPoint(x: 0, y: bottomY - 240),
          to: CGPoint(x: 0, y: bottomY))
    ctx.restoreGState()

    // Outline
    ctx.addPath(glassPath)
    ctx.setStrokeColor(navy)
    ctx.setLineWidth(20)
    ctx.setLineJoin(.round)
    ctx.strokePath()

    try writePNG(ctx, to: outRoot.appendingPathComponent("05-hourglass-split.png"))
    print("✓ 05-hourglass-split.png")
}

// MARK: - 6. Compass Dial

func renderCompassDial() throws {
    let ctx = makeContext()
    clip(ctx)

    // Dark navy radial gradient
    paint(ctx,
          radial: gradient(colors: [rgb(28, 42, 72), navyDeep]),
          center: CGPoint(x: canvas / 2, y: canvas / 2),
          radius: canvas * 0.7)

    let center = CGPoint(x: canvas / 2, y: canvas / 2)
    let dialR: CGFloat = 380

    // Outer rim
    ctx.setStrokeColor(rgb(255, 255, 255, 0.85))
    ctx.setLineWidth(8)
    ctx.addArc(center: center, radius: dialR, startAngle: 0, endAngle: τ, clockwise: false)
    ctx.strokePath()

    // 24 ticks
    for hour in 0..<24 {
        let isMajor = hour % 6 == 0
        let angle = -π / 2 + (τ) * CGFloat(hour) / 24
        let outer = CGPoint(x: center.x + cos(angle) * dialR * 0.96,
                            y: center.y + sin(angle) * dialR * 0.96)
        let inner = CGPoint(x: center.x + cos(angle) * dialR * (isMajor ? 0.84 : 0.90),
                            y: center.y + sin(angle) * dialR * (isMajor ? 0.84 : 0.90))
        ctx.setStrokeColor(rgb(255, 255, 255, isMajor ? 0.9 : 0.45))
        ctx.setLineWidth(isMajor ? 8 : 4)
        ctx.setLineCap(.round)
        ctx.move(to: inner)
        ctx.addLine(to: outer)
        ctx.strokePath()
    }

    // 5-hour arc (12 → 5h, sweeping clockwise) — Claude orange
    let arcStroke: CGFloat = 50
    ctx.setStrokeColor(claudeBright)
    ctx.setLineWidth(arcStroke)
    ctx.setLineCap(.round)
    ctx.addArc(
        center: center,
        radius: dialR * 0.62,
        startAngle: -π / 2,
        endAngle: -π / 2 + (τ) * 5 / 24,
        clockwise: false
    )
    ctx.strokePath()

    // Crosshairs (faint)
    ctx.setStrokeColor(rgb(255, 255, 255, 0.18))
    ctx.setLineWidth(2)
    ctx.move(to: CGPoint(x: center.x, y: center.y - dialR * 1.05))
    ctx.addLine(to: CGPoint(x: center.x, y: center.y + dialR * 1.05))
    ctx.strokePath()
    ctx.move(to: CGPoint(x: center.x - dialR * 1.05, y: center.y))
    ctx.addLine(to: CGPoint(x: center.x + dialR * 1.05, y: center.y))
    ctx.strokePath()

    // Center 5h label
    drawText(ctx, "5h", at: center, size: 130, weight: .bold, color: white, design: .rounded)

    // Tip dots at 0h and 5h positions on the arc
    for fraction in [CGFloat(0), CGFloat(5.0 / 24.0)] {
        let angle = -π / 2 + (τ) * fraction
        let p = CGPoint(x: center.x + cos(angle) * dialR * 0.62,
                        y: center.y + sin(angle) * dialR * 0.62)
        ctx.setFillColor(white)
        ctx.addArc(center: p, radius: 18, startAngle: 0, endAngle: τ, clockwise: false)
        ctx.fillPath()
    }

    try writePNG(ctx, to: outRoot.appendingPathComponent("06-compass-dial.png"))
    print("✓ 06-compass-dial.png")
}

// MARK: - 7. Sunrise Arc

func renderSunriseArc() throws {
    let ctx = makeContext()
    clip(ctx)

    // Dawn → dusk gradient
    paint(ctx,
          linear: gradient(
            colors: [
                rgb(248, 178, 122), // dawn pink-orange
                rgb(232, 132, 102),
                rgb(154, 117, 188), // dusk purple
                rgb(54, 76, 142)    // night blue
            ],
            locations: [0.0, 0.35, 0.70, 1.0]
          ),
          from: CGPoint(x: 0, y: canvas),
          to: CGPoint(x: 0, y: 0))

    let cx = canvas / 2
    let horizonY = canvas * 0.30
    let arcCenter = CGPoint(x: cx, y: horizonY)
    let arcR = canvas * 0.40

    // Day path arc (white, half circle above horizon)
    ctx.setStrokeColor(rgb(255, 255, 255, 0.85))
    ctx.setLineWidth(6)
    ctx.setLineCap(.round)
    let dash: [CGFloat] = [16, 18]
    ctx.setLineDash(phase: 0, lengths: dash)
    ctx.addArc(
        center: arcCenter,
        radius: arcR,
        startAngle: -π,
        endAngle: 0,
        clockwise: true
    )
    ctx.strokePath()
    ctx.setLineDash(phase: 0, lengths: [])

    // Sun (start of 5h window) — left
    let sunPos = CGPoint(x: arcCenter.x - arcR, y: arcCenter.y)
    paint(ctx,
          radial: gradient(colors: [
            rgb(255, 240, 130, 0.9),
            rgb(255, 240, 130, 0)
          ]),
          center: sunPos,
          radius: 240)
    ctx.setFillColor(rgb(255, 220, 100))
    ctx.addArc(center: sunPos, radius: 90, startAngle: 0, endAngle: τ, clockwise: false)
    ctx.fillPath()

    // Moon (end of 5h window) — right
    let moonPos = CGPoint(x: arcCenter.x + arcR, y: arcCenter.y)
    ctx.setFillColor(rgb(245, 240, 220))
    ctx.addArc(center: moonPos, radius: 80, startAngle: 0, endAngle: τ, clockwise: false)
    ctx.fillPath()
    ctx.setFillColor(rgb(54, 76, 142, 0.4))
    ctx.addArc(
        center: CGPoint(x: moonPos.x + 30, y: moonPos.y - 5),
        radius: 70, startAngle: 0, endAngle: τ, clockwise: false
    )
    ctx.fillPath()

    // Apex marker (peak of arc) — small dot indicating "5h focus"
    let apex = CGPoint(x: arcCenter.x, y: arcCenter.y + arcR)
    ctx.setFillColor(white)
    ctx.addArc(center: apex, radius: 26, startAngle: 0, endAngle: τ, clockwise: false)
    ctx.fillPath()
    ctx.setFillColor(claude)
    ctx.addArc(center: apex, radius: 14, startAngle: 0, endAngle: τ, clockwise: false)
    ctx.fillPath()

    // Horizon line
    ctx.setStrokeColor(rgb(255, 255, 255, 0.45))
    ctx.setLineWidth(4)
    ctx.move(to: CGPoint(x: 80, y: horizonY))
    ctx.addLine(to: CGPoint(x: canvas - 80, y: horizonY))
    ctx.strokePath()

    // "5h" label below horizon
    drawText(ctx, "5h",
             at: CGPoint(x: cx, y: canvas * 0.16),
             size: 200, weight: .bold,
             color: rgb(255, 255, 255, 0.95),
             design: .rounded)

    try writePNG(ctx, to: outRoot.appendingPathComponent("07-sunrise-arc.png"))
    print("✓ 07-sunrise-arc.png")
}

// MARK: - Contact sheet (3×3 grid showing all 7 with labels)

func renderContactSheet() throws {
    let cellSize: CGFloat = 360
    let labelHeight: CGFloat = 70
    let columns = 3
    let rows = 3
    let padding: CGFloat = 40
    let sheetW = CGFloat(columns) * cellSize + CGFloat(columns + 1) * padding
    let sheetH = CGFloat(rows) * (cellSize + labelHeight) + CGFloat(rows + 1) * padding + 80

    let ctx = makeContext(size: max(sheetW, sheetH))
    let actualSize = max(sheetW, sheetH)

    // Light slate background
    ctx.setFillColor(rgb(240, 242, 248))
    ctx.fill(CGRect(x: 0, y: 0, width: actualSize, height: actualSize))

    // Title
    drawText(ctx, "C5h app icon candidates",
             at: CGPoint(x: actualSize / 2, y: actualSize - 50),
             size: 38, weight: .bold,
             color: rgb(28, 36, 60),
             design: .default)

    let entries: [(String, String)] = [
        ("01-wedge-clock.png", "1. Wedge Clock"),
        ("02-activity-rings.png", "2. Activity Rings"),
        ("03-stacked-bars.png", "3. Stacked Bars"),
        ("04-numeral-5h.png", "4. Numeral 5h"),
        ("05-hourglass-split.png", "5. Hourglass Split"),
        ("06-compass-dial.png", "6. Compass Dial"),
        ("07-sunrise-arc.png", "7. Sunrise Arc")
    ]

    for (i, (filename, label)) in entries.enumerated() {
        let row = i / columns
        let col = i % columns
        let x = padding + CGFloat(col) * (cellSize + padding)
        // Reverse y because CG origin is bottom-left
        let yTop = actualSize - 100 - padding - CGFloat(row + 1) * (cellSize + labelHeight) - CGFloat(row) * padding
        let cellRect = CGRect(x: x, y: yTop + labelHeight, width: cellSize, height: cellSize)

        // Load and draw the icon
        let iconURL = outRoot.appendingPathComponent(filename)
        if let provider = CGDataProvider(url: iconURL as CFURL),
           let cg = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) {
            // Drop shadow
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.25))
            ctx.draw(cg, in: cellRect)
            ctx.restoreGState()
        }
        // Label
        drawText(ctx, label,
                 at: CGPoint(x: x + cellSize / 2, y: yTop + labelHeight / 2),
                 size: 26, weight: .semibold,
                 color: rgb(28, 36, 60),
                 design: .default)
    }

    try writePNG(ctx, to: outRoot.appendingPathComponent("00-contact-sheet.png"))
    print("✓ 00-contact-sheet.png")
}

// MARK: - Run

do {
    try renderWedgeClock()
    try renderActivityRings()
    try renderStackedBars()
    try renderNumeral5h()
    try renderHourglassSplit()
    try renderCompassDial()
    try renderSunriseArc()
    try renderContactSheet()
    print("\nAll icons rendered to \(outRoot.path)")
} catch {
    print("Error: \(error)")
    exit(1)
}
