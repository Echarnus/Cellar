// Renders Cellar's app icon to a 1024×1024 PNG with AppKit — reproducible, no external assets.
// macOS-style: a superellipse "squircle" on the standard icon grid, a layered wine gradient with a
// top sheen and inner vignette, and a cream keg with burgundy hoops and a tap (games, kept in the
// cellar, ready to pour). Run: swift Scripts/make-icon.swift <out.png>
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

// ---- Emblem: a keg (cream) seen from slightly above ----
let cx = body.midX, cy = body.midY
let cream = rgb(245, 238, 228)
let hoop = rgb(58, 14, 30)

// Geometry. The keg is a bulged cylinder; `ry` is the half-height of the elliptical rims that the
// slight top-down view exposes, so the lid and the curved hoops all share one perspective.
let kegW = S*0.42, kegH = S*0.46, bulge = S*0.045, ry = S*0.040
let left = cx - kegW/2, right = cx + kegW/2
let topY = cy + kegH/2 - S*0.02, botY = cy - kegH/2 - S*0.02

// Silhouette: bulged sides, front half of the bottom rim, back half of the top rim.
let keg = CGMutablePath()
keg.move(to: CGPoint(x: left, y: topY))
keg.addQuadCurve(to: CGPoint(x: left, y: botY), control: CGPoint(x: left - bulge, y: cy))
keg.addQuadCurve(to: CGPoint(x: right, y: botY), control: CGPoint(x: cx, y: botY - 2*ry))
keg.addQuadCurve(to: CGPoint(x: right, y: topY), control: CGPoint(x: right + bulge, y: cy))
keg.addQuadCurve(to: CGPoint(x: left, y: topY), control: CGPoint(x: cx, y: topY + 2*ry))
keg.closeSubpath()

// A curved band across the face at height `y` (follows the rim perspective), wider than the body so
// the clip trims it to the silhouette.
func band(at y: Double, height h: Double) -> CGPath {
    let p = CGMutablePath()
    let l = left - bulge - S*0.01, r = right + bulge + S*0.01
    p.move(to: CGPoint(x: l, y: y + h/2))
    p.addQuadCurve(to: CGPoint(x: r, y: y + h/2), control: CGPoint(x: cx, y: y + h/2 - 2*ry))
    p.addLine(to: CGPoint(x: r, y: y - h/2))
    p.addQuadCurve(to: CGPoint(x: l, y: y - h/2), control: CGPoint(x: cx, y: y - h/2 - 2*ry))
    p.closeSubpath()
    return p
}

// Body with a drop shadow.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -S*0.008), blur: S*0.024, color: rgb(0,0,0,0.32))
ctx.addPath(keg); ctx.setFillColor(cream); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(keg); ctx.clip()
// Cylindrical shading: lit from the left, darker toward the right edge.
let barrel = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [rgb(252, 248, 240), rgb(245, 238, 228), rgb(212, 198, 182)] as CFArray, locations: [0, 0.45, 1])!
ctx.drawLinearGradient(barrel, start: CGPoint(x: left, y: cy), end: CGPoint(x: right, y: cy), options: [])

// Hoops: two burgundy bands near the rims, each with a highlight and a shadow edge so they read as metal.
let bandH = S*0.050
for y in [topY - S*0.075, botY + S*0.095] {
    ctx.addPath(band(at: y, height: bandH)); ctx.setFillColor(hoop); ctx.fillPath()
    ctx.addPath(band(at: y + bandH/2 - S*0.005, height: S*0.010)); ctx.setFillColor(rgb(255,255,255,0.16)); ctx.fillPath()
    ctx.addPath(band(at: y - bandH/2 + S*0.004, height: S*0.008)); ctx.setFillColor(rgb(0,0,0,0.22)); ctx.fillPath()
}
ctx.restoreGState()

// Lid: the full top ellipse, slightly darker than the face, with a rim line and a centre bung.
let lid = CGRect(x: left, y: topY - ry, width: kegW, height: 2*ry)
ctx.saveGState()
ctx.addEllipse(in: lid); ctx.setFillColor(rgb(232, 222, 208)); ctx.fillPath()
ctx.addEllipse(in: lid.insetBy(dx: S*0.004, dy: S*0.003))
ctx.setStrokeColor(rgb(0,0,0,0.12)); ctx.setLineWidth(S*0.006); ctx.strokePath()
let bung = S*0.028
ctx.addEllipse(in: CGRect(x: cx - bung/2, y: topY - bung*0.32, width: bung, height: bung*0.64))
ctx.setFillColor(hoop); ctx.fillPath()
ctx.restoreGState()

// Tap on the front face, low down: a dark spout reaching below the rim, with a small handle.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -S*0.006), blur: S*0.02, color: rgb(0,0,0,0.30))
let spoutW = S*0.052, spoutTop = botY + S*0.060, spoutBot = botY - S*0.065
ctx.addPath(CGPath(roundedRect: CGRect(x: cx - spoutW/2, y: spoutBot, width: spoutW, height: spoutTop - spoutBot),
                   cornerWidth: S*0.012, cornerHeight: S*0.012, transform: nil))
ctx.setFillColor(hoop); ctx.fillPath()
let handleW = S*0.12, handleH = S*0.028
ctx.addPath(CGPath(roundedRect: CGRect(x: cx - handleW/2, y: botY + S*0.005, width: handleW, height: handleH),
                   cornerWidth: handleH/2, cornerHeight: handleH/2, transform: nil))
ctx.setFillColor(rgb(84, 24, 46)); ctx.fillPath()
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
