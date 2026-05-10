import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Docs/Icons/Fresh", isDirectory: true)
let rawRoot = root.appendingPathComponent("raw", isDirectory: true)
let finalRoot = root.appendingPathComponent("final", isDirectory: true)
let reviewRoot = root.appendingPathComponent("review", isDirectory: true)
let appIconRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("C5h/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

try FileManager.default.createDirectory(at: finalRoot, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: reviewRoot, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: appIconRoot, withIntermediateDirectories: true)

let canvas: CGFloat = 1024

struct Candidate {
    let raw: String
    let final: String
    let label: String
    let overlay: Overlay
}

enum Overlay {
    case none
    case c5h(y: CGFloat)
    case code([(String, CGColor)], y: CGFloat, size: CGFloat)
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let white = rgb(255, 255, 255)
let warm = rgb(255, 144, 72)
let cream = rgb(255, 235, 205)
let graphite = rgb(18, 24, 38)
let teal = rgb(95, 220, 200)

let candidates: [Candidate] = [
    Candidate(
        raw: "01-premium-focus-core-base.png",
        final: "01-premium-focus-core.png",
        label: "01 Premium focus core",
        overlay: .none
    ),
    Candidate(
        raw: "02-premium-bracket-prism-base.png",
        final: "02-premium-bracket-prism-c5h.png",
        label: "02 Bracket prism C5h",
        overlay: .c5h(y: 145)
    ),
    Candidate(
        raw: "03-premium-five-hour-orbit-base.png",
        final: "03-premium-five-hour-orbit.png",
        label: "03 Five-hour orbit",
        overlay: .none
    ),
    Candidate(
        raw: "04-premium-code-time-monogram-base.png",
        final: "04-premium-code-time-monogram.png",
        label: "04 Code-time monogram",
        overlay: .code([("{", cream), ("C", white), ("5", warm), ("h", white), ("}", cream)], y: 138, size: 108)
    ),
    Candidate(
        raw: "05-native-scheduler-glyph-base.png",
        final: "05-native-scheduler-glyph.png",
        label: "05 Scheduler glyph",
        overlay: .none
    ),
    Candidate(
        raw: "06-native-compact-timer-base.png",
        final: "06-native-compact-timer-c5h.png",
        label: "06 Compact timer C5h",
        overlay: .c5h(y: 150)
    ),
    Candidate(
        raw: "07-native-provider-lane-focus-base.png",
        final: "07-native-provider-lane-focus.png",
        label: "07 Provider-lane focus",
        overlay: .none
    ),
    Candidate(
        raw: "08-native-command-timer-base.png",
        final: "08-native-command-timer.png",
        label: "08 Command timer",
        overlay: .code([(">", teal), (" run", white)], y: 135, size: 92)
    ),
    Candidate(
        raw: "09-developer-editor-glow-base.png",
        final: "09-developer-editor-glow.png",
        label: "09 Editor glow",
        overlay: .none
    ),
    Candidate(
        raw: "10-developer-terminal-horizon-base.png",
        final: "10-developer-terminal-horizon-c5h.png",
        label: "10 Terminal horizon C5h",
        overlay: .c5h(y: 150)
    ),
    Candidate(
        raw: "11-developer-focused-workspace-base.png",
        final: "11-developer-focused-workspace.png",
        label: "11 Focused workspace",
        overlay: .none
    ),
    Candidate(
        raw: "12-developer-run-session-base.png",
        final: "12-developer-run-session.png",
        label: "12 run(5h) session",
        overlay: .code([("run", teal), ("(", white), ("5h", warm), (")", white)], y: 218, size: 84)
    )
]

func makeContext(width: Int, height: Int) -> CGContext {
    CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

func loadImage(_ url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw NSError(domain: "FreshIconComposer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot load \(url.path)"])
    }
    return image
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "FreshIconComposer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot create \(url.path)"])
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "FreshIconComposer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot write \(url.path)"])
    }
}

func resizedImage(_ source: CGImage, size: CGFloat) -> CGImage {
    let ctx = makeContext(width: Int(size), height: Int(size))
    ctx.interpolationQuality = .high
    ctx.draw(source, in: CGRect(x: 0, y: 0, width: size, height: size))
    return ctx.makeImage()!
}

func textFont(size: CGFloat, weight: NSFont.Weight, design: NSFontDescriptor.SystemDesign) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    let descriptor = base.fontDescriptor.withDesign(design) ?? base.fontDescriptor
    return NSFont(descriptor: descriptor, size: size) ?? base
}

func drawTextLine(
    _ ctx: CGContext,
    segments: [(String, CGColor)],
    at point: CGPoint,
    size: CGFloat,
    weight: NSFont.Weight = .black,
    design: NSFontDescriptor.SystemDesign = .rounded
) {
    let font = textFont(size: size, weight: weight, design: design)
    let attributed = NSMutableAttributedString()
    for (text, color) in segments {
        attributed.append(NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: NSColor(cgColor: color) ?? .white
            ]
        ))
    }

    let line = CTLineCreateWithAttributedString(attributed)
    let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -5), blur: 18, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.75))
    ctx.textPosition = CGPoint(
        x: point.x - bounds.width / 2 - bounds.origin.x,
        y: point.y - bounds.height / 2 - bounds.origin.y
    )
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

func drawSmallLabel(_ ctx: CGContext, _ text: String, at point: CGPoint, size: CGFloat = 22) {
    drawTextLine(ctx, segments: [(text, graphite)], at: point, size: size, weight: .semibold, design: .default)
}

func composeCandidate(_ candidate: Candidate) throws -> CGImage {
    let raw = try loadImage(rawRoot.appendingPathComponent(candidate.raw))
    let ctx = makeContext(width: Int(canvas), height: Int(canvas))
    ctx.interpolationQuality = .high
    ctx.draw(raw, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))

    switch candidate.overlay {
    case .none:
        break
    case .c5h(let y):
        drawTextLine(
            ctx,
            segments: [("C", white), ("5", warm), ("h", white)],
            at: CGPoint(x: canvas / 2, y: y),
            size: 132,
            weight: .black,
            design: .rounded
        )
    case .code(let segments, let y, let size):
        drawTextLine(
            ctx,
            segments: segments,
            at: CGPoint(x: canvas / 2, y: y),
            size: size,
            weight: .heavy,
            design: .monospaced
        )
    }

    return ctx.makeImage()!
}

func renderContactSheet() throws {
    let columns = 4
    let rows = 3
    let cell: CGFloat = 250
    let labelHeight: CGFloat = 56
    let padding: CGFloat = 28
    let titleHeight: CGFloat = 84
    let width = CGFloat(columns) * cell + CGFloat(columns + 1) * padding
    let height = titleHeight + CGFloat(rows) * (cell + labelHeight) + CGFloat(rows + 1) * padding
    let ctx = makeContext(width: Int(width), height: Int(height))
    ctx.setFillColor(rgb(240, 242, 248))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

    drawSmallLabel(ctx, "Fresh C5h app icon candidates", at: CGPoint(x: width / 2, y: height - 48), size: 34)

    for (index, candidate) in candidates.enumerated() {
        let image = try loadImage(finalRoot.appendingPathComponent(candidate.final))
        let col = index % columns
        let row = index / columns
        let x = padding + CGFloat(col) * (cell + padding)
        let y = height - titleHeight - padding - CGFloat(row + 1) * (cell + labelHeight) - CGFloat(row) * padding

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.18))
        ctx.draw(image, in: CGRect(x: x, y: y + labelHeight, width: cell, height: cell))
        ctx.restoreGState()
        drawSmallLabel(ctx, candidate.label, at: CGPoint(x: x + cell / 2, y: y + 26), size: 17)
    }

    try writePNG(ctx.makeImage()!, to: reviewRoot.appendingPathComponent("01-final-contact-sheet.png"))
}

func renderSmallSizeSheet() throws {
    let rowHeight: CGFloat = 112
    let padding: CGFloat = 28
    let labelWidth: CGFloat = 300
    let width: CGFloat = 760
    let height = CGFloat(candidates.count) * rowHeight + padding * 2 + 70
    let ctx = makeContext(width: Int(width), height: Int(height))
    ctx.setFillColor(rgb(240, 242, 248))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

    drawSmallLabel(ctx, "Small-size checks: 1024 files, 256, 64, 32 previews", at: CGPoint(x: width / 2, y: height - 44), size: 26)
    drawSmallLabel(ctx, "256", at: CGPoint(x: labelWidth + 78, y: height - 84), size: 15)
    drawSmallLabel(ctx, "64", at: CGPoint(x: labelWidth + 210, y: height - 84), size: 15)
    drawSmallLabel(ctx, "32", at: CGPoint(x: labelWidth + 300, y: height - 84), size: 15)

    for (index, candidate) in candidates.enumerated() {
        let image = try loadImage(finalRoot.appendingPathComponent(candidate.final))
        let y = height - padding - 100 - CGFloat(index + 1) * rowHeight
        drawSmallLabel(ctx, candidate.label, at: CGPoint(x: padding + labelWidth / 2 - 18, y: y + 45), size: 17)

        ctx.draw(image, in: CGRect(x: labelWidth + 30, y: y + 6, width: 88, height: 88))
        ctx.draw(image, in: CGRect(x: labelWidth + 178, y: y + 18, width: 64, height: 64))
        ctx.draw(image, in: CGRect(x: labelWidth + 284, y: y + 34, width: 32, height: 32))
    }

    try writePNG(ctx.makeImage()!, to: reviewRoot.appendingPathComponent("02-small-size-check.png"))
}

func exportAppIcon(from image: CGImage) throws {
    let slots: [(String, CGFloat)] = [
        ("AppIcon-16.png", 16),
        ("AppIcon-16@2x.png", 32),
        ("AppIcon-32.png", 32),
        ("AppIcon-32@2x.png", 64),
        ("AppIcon-128.png", 128),
        ("AppIcon-128@2x.png", 256),
        ("AppIcon-256.png", 256),
        ("AppIcon-256@2x.png", 512),
        ("AppIcon-512.png", 512),
        ("AppIcon-512@2x.png", 1024)
    ]

    for (filename, size) in slots {
        try writePNG(resizedImage(image, size: size), to: appIconRoot.appendingPathComponent(filename))
    }
}

for candidate in candidates {
    let image = try composeCandidate(candidate)
    try writePNG(image, to: finalRoot.appendingPathComponent(candidate.final))
    print("Rendered \(candidate.final)")
}

try renderContactSheet()
try renderSmallSizeSheet()

let winner = try loadImage(finalRoot.appendingPathComponent("02-premium-bracket-prism-c5h.png"))
try exportAppIcon(from: winner)
print("Installed AppIcon from 02-premium-bracket-prism-c5h.png")
