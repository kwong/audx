#!/usr/bin/env swift

import AppKit
import CoreGraphics

// Generate macOS app icon from AppIcon.svg

let svgPath = "AppIcon.svg"
let iconsetDir = "audx.iconset"
let fm = FileManager.default

guard let svgData = fm.contents(atPath: svgPath) else {
    print("Error: Cannot read \(svgPath)")
    exit(1)
}

guard let svgImage = NSImage(data: svgData) else {
    print("Error: Cannot parse SVG")
    exit(1)
}

func renderPNG(image: NSImage, size: Int, path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                pixelsWide: size, pixelsHigh: size,
                                bitsPerSample: 8, samplesPerPixel: 4,
                                hasAlpha: true, isPlanar: false,
                                colorSpaceName: .deviceRGB,
                                bytesPerRow: 0, bitsPerPixel: 0)!
    
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    
    let data = rep.representation(using: .png, properties: [.interlaced: false])!
    try! data.write(to: URL(fileURLWithPath: path))
}

// Generate all icon sizes
try? fm.removeItem(atPath: iconsetDir)
try! fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, px) in sizes {
    renderPNG(image: svgImage, size: px, path: "\(iconsetDir)/\(name)")
    print("Generated \(name) (\(px)x\(px))")
}

print("Converting to icns...")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconsetDir]
try! task.run()
task.waitUntilExit()

try? fm.removeItem(atPath: "AppIcon.icns")
try! fm.moveItem(atPath: "audx.icns", toPath: "AppIcon.icns")
try? fm.removeItem(atPath: iconsetDir)

print("Done! AppIcon.icns created from SVG.")
