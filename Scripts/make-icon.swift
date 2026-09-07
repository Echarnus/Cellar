// Renders Cellar's app icon to a 1024×1024 PNG with AppKit — reproducible, no external assets.
// Motif: a wine-cellar arch (Cellar runs games on *Wine*) over a burgundy gradient, with a green
// play triangle badge (it plays games). Run: swift Scripts/make-icon.swift <out.png>
import AppKit

let size = 1024.0
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ r: Double, _ g: Double, _ b: Double) -> CGColor {
    CGColor(red: r/255, green: g/255, blue: b/255, alpha: 1)
}

// Rounded-square background with a burgundy → plum vertical gradient (macOS "squircle"-ish radius).
let rect = CGRect(x: 0, y: 0, width: size, height: size)
let bgPath = CGPath(roundedRect: rect.insetBy(dx: size*0.09, dy: size*0.09),
                    cornerWidth: size*0.22, cornerHeight: size*0.22, transform: nil)
ctx.saveGState()
ctx.addPath(bgPath); ctx.clip()
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(122, 30, 59), color(58, 14, 28)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
ctx.restoreGState()

// Cellar arch: a cream rounded archway (rectangle + semicircle top), centered.
let cx = size/2
let archW = size*0.40, archBottom = size*0.30, archStraight = size*0.20
let archLeft = cx - archW/2, archRight = cx + archW/2
let arch = CGMutablePath()
arch.move(to: CGPoint(x: archLeft, y: archBottom))
arch.addLine(to: CGPoint(x: archLeft, y: archBottom + archStraight))
arch.addArc(center: CGPoint(x: cx, y: archBottom + archStraight),
            radius: archW/2, startAngle: .pi, endAngle: 0, clockwise: true)
arch.addLine(to: CGPoint(x: archRight, y: archBottom))
arch.closeSubpath()
ctx.addPath(arch)
ctx.setFillColor(color(244, 236, 224)) // cream
ctx.fillPath()

// Inner arch shadow line for depth.
ctx.addPath(arch)
ctx.setStrokeColor(color(58, 14, 28).copy(alpha: 0.25)!)
ctx.setLineWidth(size*0.012)
ctx.strokePath()

// Green play triangle centered in the arch — it plays games.
let t = size*0.11
let tx = cx - t*0.42, ty = size*0.52
let tri = CGMutablePath()
tri.move(to: CGPoint(x: tx, y: ty + t))
tri.addLine(to: CGPoint(x: tx, y: ty - t))
tri.addLine(to: CGPoint(x: tx + t*1.5, y: ty))
tri.closeSubpath()
ctx.addPath(tri)
ctx.setFillColor(color(52, 199, 89)) // system green
ctx.fillPath()

NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
