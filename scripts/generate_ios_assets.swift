import AppKit
import Foundation

struct AppIconImage: Decodable {
  let size: String?
  let idiom: String?
  let filename: String?
  let scale: String?
}

struct AppIconContents: Decodable {
  let images: [AppIconImage]
}

func parseBaseSize(_ size: String) -> CGFloat? {
  let parts = size.split(separator: "x")
  if parts.count != 2 { return nil }
  return CGFloat(Double(parts[0]) ?? 0)
}

func parseScale(_ scale: String) -> CGFloat? {
  let cleaned = scale.replacingOccurrences(of: "x", with: "")
  return CGFloat(Double(cleaned) ?? 0)
}

func color(hex: String) -> NSColor {
  var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
  if value.hasPrefix("#") { value.removeFirst() }
  if value.count != 6 { return NSColor.black }
  let r = CGFloat(Int(value.prefix(2), radix: 16) ?? 0) / 255.0
  let g = CGFloat(Int(value.dropFirst(2).prefix(2), radix: 16) ?? 0) / 255.0
  let b = CGFloat(Int(value.dropFirst(4).prefix(2), radix: 16) ?? 0) / 255.0
  return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1.0)
}

func renderBitmap(size: Int, draw: (NSRect) -> Void) throws -> NSBitmapImageRep {
  guard
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: size,
      pixelsHigh: size,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    )
  else { throw NSError(domain: "bitmap", code: 1) }

  rep.size = NSSize(width: size, height: size)
  guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
    throw NSError(domain: "bitmap", code: 2)
  }

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = ctx
  ctx.cgContext.interpolationQuality = .high

  let rect = NSRect(x: 0, y: 0, width: size, height: size)
  draw(rect)

  NSGraphicsContext.restoreGraphicsState()
  return rep
}

func renderIconRep(size: Int) throws -> NSBitmapImageRep {
  return try renderBitmap(size: size) { rect in
    let bg = color(hex: "#1E3A8A")
    bg.setFill()
    rect.fill()

    let gridColor = NSColor.white.withAlphaComponent(0.95)
    gridColor.setFill()

    let padding = CGFloat(size) * 0.18
    let gap = CGFloat(size) * 0.06
    let tile = (CGFloat(size) - padding * 2 - gap) / 2

    let r: CGFloat = CGFloat(size) * 0.09

    let p1 = NSRect(x: padding, y: padding + tile + gap, width: tile, height: tile)
    let p2 = NSRect(x: padding + tile + gap, y: padding + tile + gap, width: tile, height: tile)
    let p3 = NSRect(x: padding, y: padding, width: tile, height: tile)
    let p4 = NSRect(x: padding + tile + gap, y: padding, width: tile, height: tile)

    NSBezierPath(roundedRect: p1, xRadius: r, yRadius: r).fill()
    NSBezierPath(roundedRect: p2, xRadius: r, yRadius: r).fill()
    NSBezierPath(roundedRect: p3, xRadius: r, yRadius: r).fill()
    NSBezierPath(roundedRect: p4, xRadius: r, yRadius: r).fill()
  }
}

func renderLaunchRep(size: Int) throws -> NSBitmapImageRep {
  return try renderBitmap(size: size) { rect in
    let bg = color(hex: "#0B1220")
    bg.setFill()
    rect.fill()

    let iconSize = Int(CGFloat(size) * 0.35)
    let iconSizeF = CGFloat(iconSize)
    let iconRect = NSRect(
      x: (CGFloat(size) - iconSizeF) / 2,
      y: (CGFloat(size) - iconSizeF) / 2,
      width: iconSizeF,
      height: iconSizeF
    )
    if let icon = try? renderIconRep(size: iconSize) {
      icon.draw(in: iconRect)
    }
  }
}

func writePng(_ rep: NSBitmapImageRep, to url: URL) throws {
  guard let data = rep.representation(using: .png, properties: [:]) else {
    throw NSError(domain: "png", code: 1)
  }
  try data.write(to: url, options: .atomic)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appIconDir = root.appendingPathComponent("ios/Runner/Assets.xcassets/AppIcon.appiconset")
let appIconContentsUrl = appIconDir.appendingPathComponent("Contents.json")
let launchDir = root.appendingPathComponent("ios/Runner/Assets.xcassets/LaunchImage.imageset")
let launchContentsUrl = launchDir.appendingPathComponent("Contents.json")

let decoder = JSONDecoder()
let appIconContents = try decoder.decode(AppIconContents.self, from: Data(contentsOf: appIconContentsUrl))

for img in appIconContents.images {
  guard let filename = img.filename else { continue }
  guard let sizeStr = img.size, let base = parseBaseSize(sizeStr) else { continue }
  guard let scaleStr = img.scale, let scale = parseScale(scaleStr) else { continue }
  let px = Int(round(base * scale))
  let rendered = try renderIconRep(size: px)
  try writePng(rendered, to: appIconDir.appendingPathComponent(filename))
}

let launchContents = try decoder.decode(AppIconContents.self, from: Data(contentsOf: launchContentsUrl))
for img in launchContents.images {
  guard let filename = img.filename else { continue }
  let scaleStr = img.scale ?? "1x"
  let scale = parseScale(scaleStr) ?? 1
  let px = Int(1024 * scale)
  let rendered = try renderLaunchRep(size: px)
  try writePng(rendered, to: launchDir.appendingPathComponent(filename))
}

print("Generated iOS assets.")
