// Draws the installer DMG's window background with AppKit — reproducible, no external assets, the
// same way make-icon.swift draws the app icon. Run: swift Scripts/make-dmg-background.swift <out-dir>
// Writes background.png (660×420) and background@2x.png; make-dmg.sh joins them into one HiDPI TIFF.
//
// The layout is shared with make-dmg.sh, which places the icons on top of it: Cellar.app centred
// at (170, 185), Applications at (490, 185), the "Licence and Read Me" folder at (330, 330), in
// points from the top-left. Move one and you must move the other.
//
// The colour is not a free choice. Finder draws icon labels black in light mode and white in dark
// mode, straight onto this image, and neither can be changed per window. So the field behind the
// labels is a mid-tone whose contrast is ≥ 4.5:1 against both (#8A6F7C: 4.52 white, 4.65 black),
// tinted towards the icon's wine rather than a flat grey.
import AppKit

let width = 660.0, height = 420.0
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func render(scale: Double, to path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale),
                               pixelsHigh: Int(height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)  // points, so the TIFF carries 72 and 144 dpi
    NSGraphicsContext.saveGraphicsState()
    let base = NSGraphicsContext(bitmapImageRep: rep)!
    // Flipped, so every coordinate below reads top-down like the Finder positions in make-dmg.sh.
    let cg = base.cgContext
    cg.translateBy(x: 0, y: height * scale)
    cg.scaleBy(x: scale, y: -scale)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    let full = NSRect(x: 0, y: 0, width: width, height: height)

    // A vertical wine-grey wash, lighter at the top where the heading sits.
    NSGradient(starting: rgb(0x95, 0x79, 0x86), ending: rgb(0x7F, 0x64, 0x71))!
        .draw(in: full, angle: 90)
    // A soft sheen behind the heading — light from above, as on the icon.
    NSGradient(colors: [rgb(255, 255, 255, 0.16), rgb(255, 255, 255, 0)])!
        .draw(fromCenter: NSPoint(x: width / 2, y: -40), radius: 0,
              toCenter: NSPoint(x: width / 2, y: -40), radius: 300, options: [])

    func centred(_ text: String, y: Double, font: NSFont, alpha: Double = 1) {
        let shadow = NSShadow()
        shadow.shadowColor = rgb(0x3A, 0x22, 0x2E, 0.35)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 2
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: rgb(255, 255, 255, alpha), .shadow: shadow,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: (width - size.width) / 2, y: y), withAttributes: attributes)
    }
    centred("Drag Cellar into Applications", y: 30, font: .systemFont(ofSize: 22, weight: .semibold))
    centred("Then open Cellar from your Applications folder.", y: 64,
            font: .systemFont(ofSize: 13, weight: .regular), alpha: 0.92)

    // The arrow from the app to Applications: a dotted shaft and a solid head, in the gap between
    // the two 100-point icons.
    rgb(255, 255, 255, 0.95).setFill()
    let arrowY = 185.0, shaftStart = 262.0, tip = 398.0
    var x = shaftStart
    while x < tip - 24 {
        NSBezierPath(roundedRect: NSRect(x: x, y: arrowY - 3, width: 8, height: 6), xRadius: 3, yRadius: 3).fill()
        x += 14
    }
    let head = NSBezierPath()
    head.move(to: NSPoint(x: tip - 22, y: arrowY - 14))
    head.line(to: NSPoint(x: tip, y: arrowY))
    head.line(to: NSPoint(x: tip - 22, y: arrowY + 14))
    head.close()
    head.fill()

    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("could not encode \(path)\n".utf8)); exit(1)
    }
    do { try png.write(to: URL(fileURLWithPath: path)) } catch {
        FileHandle.standardError.write(Data("could not write \(path): \(error)\n".utf8)); exit(1)
    }
}

render(scale: 1, to: "\(outDir)/background.png")
render(scale: 2, to: "\(outDir)/background@2x.png")
print("Wrote \(outDir)/background.png and background@2x.png")
