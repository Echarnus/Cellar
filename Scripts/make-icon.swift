// Renders Cellar's app icon to a 1024×1024 PNG with AppKit — reproducible, no external assets.
// macOS-style: a superellipse "squircle" on the standard icon grid, a layered wine gradient with a
// top sheen and inner vignette, and a cream wine glass whose bowl holds a green play triangle
// (Cellar plays games on *Wine*). Run: swift Scripts/make-icon.swift <out.png>
import AppKit

let S = 1024.0
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(red: r/255, green: g/255, blue: b/255, alpha: a)
}

// Superellipse (macOS squircle). Content sits on the standard grid: ~824/1024 with rounded margins.
func squircle(_ rect: CGRect, n: Double = 5.0) -> CGPath {
    let p = CGMutablePath()
    let cx = rect.midX, cy = rect.midY, a = rect.width/2, b = rect.height/2
    let steps = 720
    for i in 0...steps {
        let t = Double(i)/Double(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * copysign(pow(abs(ct), 2/n), ct)
        let y = cy + b * copysign(pow(abs(st), 2/n), st)
        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
    }
    p.closeSubpath()
    return p
}

let margin = S * 0.09
let body = CGRect(x: margin, y: margin, width: S - 2*margin, height: S - 2*margin)
let shape = squircle(body)

// Soft ambient shadow under the icon.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -S*0.012), blur: S*0.03, color: rgb(0,0,0,0.35))
ctx.addPath(shape); ctx.setFillColor(rgb(0,0,0,1)); ctx.fillPath()
ctx.restoreGState()

// Wine gradient fill (diagonal), clipped to the squircle.
ctx.saveGState()
ctx.addPath(shape); ctx.clip()
let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [rgb(158, 38, 74), rgb(112, 26, 55), rgb(60, 15, 30)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: body.minX, y: body.maxY),
                       end: CGPoint(x: body.maxX, y: body.minY), options: [])
// Top sheen: a soft white radial near the top.
let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [rgb(255,255,255,0.22), rgb(255,255,255,0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(sheen, startCenter: CGPoint(x: body.midX, y: body.maxY - body.height*0.06), startRadius: 0,
                       endCenter: CGPoint(x: body.midX, y: body.maxY - body.height*0.06), endRadius: body.width*0.75, options: [])
// Inner vignette at the bottom for depth.
let vig = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [rgb(0,0,0,0), rgb(0,0,0,0.28)] as CFArray, locations: [0.5, 1])!
ctx.drawLinearGradient(vig, start: CGPoint(x: body.midX, y: body.maxY),
                       end: CGPoint(x: body.midX, y: body.minY), options: [])
ctx.restoreGState()

// Inner top rim highlight (thin bright stroke along the upper edge).
ctx.saveGState()
ctx.addPath(shape); ctx.clip()
ctx.addPath(squircle(body.insetBy(dx: S*0.006, dy: S*0.006)))
ctx.setStrokeColor(rgb(255,255,255,0.18)); ctx.setLineWidth(S*0.010); ctx.strokePath()
ctx.restoreGState()

// ---- Emblem: a wine glass (cream) with a green play triangle in the bowl ----
let cx = body.midX
let cream = rgb(245, 238, 228)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -S*0.006), blur: S*0.02, color: rgb(0,0,0,0.30))

// Bowl: a rounded cup (half-ellipse top + curved bottom).
let bowlW = S*0.34, bowlTop = body.midY + S*0.20, bowlDepth = S*0.20
let bowl = CGMutablePath()
bowl.move(to: CGPoint(x: cx - bowlW/2, y: bowlTop))
bowl.addQuadCurve(to: CGPoint(x: cx + bowlW/2, y: bowlTop),
                  control: CGPoint(x: cx, y: bowlTop + S*0.03)) // gentle rim
bowl.addCurve(to: CGPoint(x: cx, y: bowlTop - bowlDepth),
              control1: CGPoint(x: cx + bowlW/2, y: bowlTop - bowlDepth*0.55),
              control2: CGPoint(x: cx + bowlW*0.28, y: bowlTop - bowlDepth))
bowl.addCurve(to: CGPoint(x: cx - bowlW/2, y: bowlTop),
              control1: CGPoint(x: cx - bowlW*0.28, y: bowlTop - bowlDepth),
              control2: CGPoint(x: cx - bowlW/2, y: bowlTop - bowlDepth*0.55))
bowl.closeSubpath()
ctx.addPath(bowl); ctx.setFillColor(cream); ctx.fillPath()

// Stem + base.
let stemTop = bowlTop - bowlDepth
let baseY = body.midY - S*0.20
let stemW = S*0.028
ctx.setShadow(offset: .zero, blur: 0, color: rgb(0,0,0,0))
let stem = CGRect(x: cx - stemW/2, y: baseY, width: stemW, height: stemTop - baseY)
ctx.addRect(stem); ctx.setFillColor(cream); ctx.fillPath()
let baseW = S*0.22, baseH = S*0.03
let base = CGPath(roundedRect: CGRect(x: cx - baseW/2, y: baseY - baseH/2, width: baseW, height: baseH),
                  cornerWidth: baseH/2, cornerHeight: baseH/2, transform: nil)
ctx.addPath(base); ctx.setFillColor(cream); ctx.fillPath()
ctx.restoreGState()

// Green play triangle inside the bowl (gradient + subtle depth).
let t = S*0.085
let tx = cx - t*0.34, ty = bowlTop - bowlDepth*0.5
let tri = CGMutablePath()
tri.move(to: CGPoint(x: tx, y: ty + t))
tri.addLine(to: CGPoint(x: tx, y: ty - t))
tri.addLine(to: CGPoint(x: tx + t*1.5, y: ty))
tri.closeSubpath()
ctx.saveGState()
ctx.addPath(tri); ctx.clip()
let green = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [rgb(60, 214, 108), rgb(40, 170, 84)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(green, start: CGPoint(x: tx, y: ty + t), end: CGPoint(x: tx, y: ty - t), options: [])
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
