// Generates the tvOS app icon + top shelf asset catalog for FooTube.
// Regenerate (deterministic, re-runnable): swift scripts/make-icon.swift
// Writes App/Assets.xcassets/App Icon & Top Shelf Image.brandassets/** (PNGs + Contents.json) and
// App/Assets.xcassets/AppArtwork.imageset, the icon flattened into one image for in-app use (Settings).

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("App/Assets.xcassets")
let brand = root.appendingPathComponent("App Icon & Top Shelf Image.brandassets")
let artworkSet = root.appendingPathComponent("AppArtwork.imageset")
let info: [String: Any] = ["author": "xcode", "version": 1]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func writeJSON(_ object: [String: Any], to dir: URL) {
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: dir.appendingPathComponent("Contents.json"))
    } catch { fail("write json \(dir.path): \(error)") }
}

func render(_ width: Int, _ height: Int, opaque: Bool, _ draw: (CGContext, CGFloat, CGFloat) -> Void) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    let alpha = opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: alpha.rawValue) else { fail("context") }
    ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
    draw(ctx, CGFloat(width), CGFloat(height))
    guard let image = ctx.makeImage() else { fail("makeImage") }
    return image
}

func savePNG(_ image: CGImage, _ url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fail("dest \(url.path)") }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) {
        fail("finalize \(url.path)")
    }
}

func background(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
    let colors = [CGColor(srgbRed: 0.86, green: 0.12, blue: 0.14, alpha: 1),
                  CGColor(srgbRed: 0.42, green: 0.03, blue: 0.06, alpha: 1)] as CFArray
    guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors,
                                    locations: [0, 1]) else { fail("gradient") }
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])
}

/// Rounded play triangle centred at `center`, `size` = triangle height.
func playGlyph(_ ctx: CGContext, center: CGPoint, size: CGFloat) {
    let r = size * 0.12
    let half = size / 2
    let width = size * 0.88
    let a = CGPoint(x: center.x - width * 0.4, y: center.y + half)
    let b = CGPoint(x: center.x + width * 0.6, y: center.y)
    let c = CGPoint(x: center.x - width * 0.4, y: center.y - half)
    let path = CGMutablePath()
    path.move(to: CGPoint(x: (a.x + c.x) / 2, y: (a.y + c.y) / 2))
    path.addArc(tangent1End: a, tangent2End: b, radius: r)
    path.addArc(tangent1End: b, tangent2End: c, radius: r)
    path.addArc(tangent1End: c, tangent2End: a, radius: r)
    path.closeSubpath()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.03), blur: size * 0.08,
                  color: CGColor(gray: 0, alpha: 0.35))
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.addPath(path)
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
}

func wordmark(_ ctx: CGContext, _ text: String, fontSize: CGFloat, origin: CGPoint) {
    let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, fontSize, nil)
    let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    ctx.textPosition = origin
    CTLineDraw(line, ctx)
}

// MARK: - App icon image stacks

func iconStack(name: String, base: (Int, Int), scales: [Int]) {
    let stack = brand.appendingPathComponent("\(name).imagestack")
    writeJSON(["info": info, "layers": [["filename": "Front.imagestacklayer"],
                                        ["filename": "Back.imagestacklayer"]]], to: stack)
    for layer in ["Front", "Back"] {
        let layerDir = stack.appendingPathComponent("\(layer).imagestacklayer")
        writeJSON(["info": info], to: layerDir)
        let set = layerDir.appendingPathComponent("Content.imageset")
        var images: [[String: Any]] = []
        for scale in scales {
            let file = "\(layer.lowercased())@\(scale)x.png"
            images.append(["filename": file, "idiom": "tv", "scale": "\(scale)x"])
            let w = base.0 * scale, h = base.1 * scale
            let image = render(w, h, opaque: layer == "Back") { ctx, w, h in
                if layer == "Back" {
                    background(ctx, w, h)
                } else {
                    playGlyph(ctx, center: CGPoint(x: w / 2, y: h / 2), size: h * 0.46)
                }
            }
            writeJSON(["info": info, "images": images], to: set)
            savePNG(image, set.appendingPathComponent(file))
        }
    }
}

// MARK: - In-app artwork

/// The app icon's two layers drawn into one opaque image.
func artwork(base: (Int, Int), scales: [Int]) {
    var images: [[String: Any]] = []
    for scale in scales {
        let file = "artwork@\(scale)x.png"
        images.append(["filename": file, "idiom": "tv", "scale": "\(scale)x"])
        let image = render(base.0 * scale, base.1 * scale, opaque: true) { ctx, w, h in
            background(ctx, w, h)
            playGlyph(ctx, center: CGPoint(x: w / 2, y: h / 2), size: h * 0.46)
        }
        writeJSON(["info": info, "images": images], to: artworkSet)
        savePNG(image, artworkSet.appendingPathComponent(file))
    }
}

// MARK: - Top shelf

func topShelf(name: String, base: (Int, Int)) {
    let set = brand.appendingPathComponent("\(name).imageset")
    var images: [[String: Any]] = []
    for scale in [1, 2] {
        let file = "topshelf@\(scale)x.png"
        images.append(["filename": file, "idiom": "tv", "scale": "\(scale)x"])
        let image = render(base.0 * scale, base.1 * scale, opaque: true) { ctx, w, h in
            background(ctx, w, h)
            let glyph = h * 0.34
            let fontSize = h * 0.26
            let textWidth = fontSize * 4.3
            let total = glyph + glyph * 0.35 + textWidth
            let startX = (w - total) / 2
            playGlyph(ctx, center: CGPoint(x: startX + glyph / 2, y: h / 2), size: glyph)
            wordmark(ctx, "FooTube", fontSize: fontSize,
                     origin: CGPoint(x: startX + glyph * 1.35, y: h / 2 - fontSize * 0.36))
        }
        writeJSON(["info": info, "images": images], to: set)
        savePNG(image, set.appendingPathComponent(file))
    }
}

try? FileManager.default.removeItem(at: brand)
try? FileManager.default.removeItem(at: artworkSet)
writeJSON(["info": info], to: root)
writeJSON([
    "info": info,
    "assets": [
        ["filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"],
        ["filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"],
        ["filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"],
        ["filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"],
    ],
], to: brand)
iconStack(name: "App Icon", base: (400, 240), scales: [1, 2])
iconStack(name: "App Icon - App Store", base: (1280, 768), scales: [1])
topShelf(name: "Top Shelf Image", base: (1920, 720))
topShelf(name: "Top Shelf Image Wide", base: (2320, 720))
artwork(base: (400, 240), scales: [1, 2])
print("Wrote \(brand.path) and \(artworkSet.path)")
