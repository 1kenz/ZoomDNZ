import AppKit

enum Tool: Int {
    case move, pen, line, arrow, rect, marker, text, step, blur, ellipse, freeMarker
}

struct Annotation {
    var tool: Tool
    var points: [CGPoint] = []
    var widths: [CGFloat] = []      // per-point stroke width (pressure) for the pen
    var color: NSColor
    var width: CGFloat
    var text: String = ""
    var number: Int = 0

    var start: CGPoint { points.first ?? .zero }
    var end: CGPoint { points.last ?? .zero }
    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    mutating func translate(by d: CGPoint) {
        points = points.map { CGPoint(x: $0.x + d.x, y: $0.y + d.y) }
    }
}

/// Draws into a top-left-origin (flipped) CGContext; used both on screen and for export.
struct SceneRenderer {
    let image: CGImage
    let bounds: CGRect

    func drawBackground(_ ctx: CGContext) {
        Self.drawFlipped(image, in: bounds, ctx)
    }

    static func drawFlipped(_ img: CGImage, in rect: CGRect, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }

    private func withText(_ ctx: CGContext, _ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    func draw(_ a: Annotation, _ ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setStrokeColor(a.color.cgColor)
        ctx.setFillColor(a.color.cgColor)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch a.tool {
        case .pen:
            guard !a.points.isEmpty else { return }
            if a.points.count == 1 {
                let r = a.widths.first ?? a.width
                ctx.fillEllipse(in: CGRect(x: a.start.x - r / 2, y: a.start.y - r / 2, width: r, height: r))
                return
            }
            for i in 1..<a.points.count {
                ctx.setLineWidth(i < a.widths.count ? a.widths[i] : a.width)
                ctx.move(to: a.points[i - 1])
                ctx.addLine(to: a.points[i])
                ctx.strokePath()
            }
        case .line:
            ctx.setLineWidth(a.width)
            ctx.move(to: a.start); ctx.addLine(to: a.end); ctx.strokePath()
        case .arrow:
            let s = a.start, e = a.end
            let angle = atan2(e.y - s.y, e.x - s.x)
            let head = max(14, a.width * 4.5)
            ctx.setLineWidth(a.width)
            ctx.move(to: s)
            ctx.addLine(to: CGPoint(x: e.x - cos(angle) * head * 0.6, y: e.y - sin(angle) * head * 0.6))
            ctx.strokePath()
            let p1 = CGPoint(x: e.x - head * cos(angle - .pi / 7), y: e.y - head * sin(angle - .pi / 7))
            let p2 = CGPoint(x: e.x - head * cos(angle + .pi / 7), y: e.y - head * sin(angle + .pi / 7))
            ctx.move(to: e); ctx.addLine(to: p1); ctx.addLine(to: p2); ctx.closePath(); ctx.fillPath()
        case .rect:
            ctx.setLineWidth(a.width)
            ctx.stroke(a.rect)
        case .marker:
            ctx.setLineCap(.butt)
            ctx.setLineWidth(max(14, a.width * 5))
            ctx.setStrokeColor(a.color.withAlphaComponent(0.4).cgColor)
            ctx.move(to: a.start); ctx.addLine(to: a.end); ctx.strokePath()
        case .blur:
            pixelate(a.rect, ctx)
        case .text:
            let font = NSFont.systemFont(ofSize: max(14, a.width * 5 + 8), weight: .semibold)
            withText(ctx) {
                (a.text as NSString).draw(at: a.start, withAttributes: [.font: font, .foregroundColor: a.color])
            }
        case .step:
            let r = 10 + a.width * 1.5
            ctx.fillEllipse(in: CGRect(x: a.start.x - r, y: a.start.y - r, width: 2 * r, height: 2 * r))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: r * 1.1, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let str = "\(a.number)" as NSString
            let size = str.size(withAttributes: attrs)
            withText(ctx) {
                str.draw(at: CGPoint(x: a.start.x - size.width / 2, y: a.start.y - size.height / 2), withAttributes: attrs)
            }
        case .ellipse:
            ctx.setLineWidth(a.width)
            ctx.strokeEllipse(in: a.rect)
        case .freeMarker:
            guard a.points.count > 1 else { return }
            ctx.setLineCap(.butt)
            ctx.setLineWidth(max(14, a.width * 5))
            ctx.setStrokeColor(a.color.withAlphaComponent(0.4).cgColor)
            ctx.addLines(between: a.points)
            ctx.strokePath()
        case .move:
            break
        }
    }

    /// Pixelates the region (to hide sensitive data).
    private func pixelate(_ r: CGRect, _ ctx: CGContext) {
        let s = CGFloat(image.width) / bounds.width
        let px = CGRect(x: r.minX * s, y: r.minY * s, width: r.width * s, height: r.height * s).integral
        guard px.width >= 2, px.height >= 2, let crop = image.cropping(to: px) else { return }
        let block: CGFloat = 12
        let sw = max(1, Int(px.width / block)), sh = max(1, Int(px.height / block))
        guard let small = CGContext(data: nil, width: sw, height: sh, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        small.interpolationQuality = .medium
        small.draw(crop, in: CGRect(x: 0, y: 0, width: sw, height: sh))
        guard let tiny = small.makeImage() else { return }
        ctx.interpolationQuality = .none
        Self.drawFlipped(tiny, in: r, ctx)
    }
}
