// Draws MyRemote's icon, a hand on a blue gradient, for the Mac app and the Remote. The hand is Lucide's
// pointer from the Remote's sprite (see THIRD_PARTY_NOTICES.md), not the menubar's SF Symbol: Apple's
// terms don't allow SF Symbols in app icons.
//
//   swift scripts/icons.swift
//
// Writes scripts/AppIcon.icns (bundle.sh copies it into the app) and remote/icons/ (the Home Screen
// icon and the manifest's). The Mac icon sits in macOS's rounded square with a shadow; the Remote's
// fill the whole square, since iOS rounds the corners itself and turns transparency black.
import AppKit

let top = NSColor(srgbRed: 0.36, green: 0.55, blue: 1.0, alpha: 1)
let bottom = NSColor(srgbRed: 0.18, green: 0.24, blue: 0.80, alpha: 1)

func png(pixels: Int, draw: (CGFloat) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

/// Lucide's pointer, white, as the Remote draws it, read from the sprite in `remote/index.html`.
let pointer: NSImage = {
    let html = try! String(contentsOf: root.appending(path: "remote/index.html"), encoding: .utf8)
    let paths = String(html.firstMatch(of: #/<symbol id="i-pointer" viewBox="0 0 24 24">(.*?)<\/symbol>/#)!.1)
    let open = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">"##
    return NSImage(data: Data((open + paths + "</svg>").utf8))!
}()

/// The white hand, `scale` of the side tall, centred in `rect`.
func hand(in rect: NSRect, scale: CGFloat) {
    let side = rect.height * scale
    pointer.draw(in: NSRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side))
}

func macIcon(_ side: CGFloat) {
    // macOS's icon grid: an 824/1024 body, corner radius 185/1024.
    let unit = side / 1024
    let body = NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * unit, yRadius: 185 * unit)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 20 * unit
    shadow.shadowOffset = NSSize(width: 0, height: -10 * unit)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: top, ending: bottom)!.draw(in: shape, angle: -90)
    hand(in: body, scale: 470 / 824)
}

func remoteIcon(_ side: CGFloat) {
    let square = NSRect(x: 0, y: 0, width: side, height: side)
    NSGradient(starting: top, ending: bottom)!.draw(in: square, angle: -90)
    // Small enough to stay inside a maskable icon's safe zone, the middle 80%.
    hand(in: square, scale: 0.58)
}

let fm = FileManager.default

let iconset = fm.temporaryDirectory.appending(path: "MyRemote-\(UUID().uuidString).iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: iconset) }
for points in [16, 32, 128, 256, 512] {
    try png(pixels: points, draw: macIcon).write(to: iconset.appending(path: "icon_\(points)x\(points).png"))
    try png(pixels: points * 2, draw: macIcon).write(to: iconset.appending(path: "icon_\(points)x\(points)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(filePath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path(percentEncoded: false),
                      "-o", root.appending(path: "scripts/AppIcon.icns").path(percentEncoded: false)]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }

let icons = root.appending(path: "remote/icons")
try fm.createDirectory(at: icons, withIntermediateDirectories: true)
try png(pixels: 180, draw: remoteIcon).write(to: icons.appending(path: "apple-touch-icon.png"))
for pixels in [192, 512] {
    try png(pixels: pixels, draw: remoteIcon).write(to: icons.appending(path: "icon-\(pixels).png"))
}
print("Wrote scripts/AppIcon.icns and remote/icons/")
