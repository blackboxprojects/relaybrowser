import AppKit

/// Fork: the app icons to choose from in Settings › Custom, drawn here
/// rather than kept as pictures: four traditional patterns in gold on a
/// light or a dark plate.
enum ForkIconKind: String, CaseIterable, Identifiable {
    case standard, asanoha, hexagons, knot, waves
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: return "Relay"
        case .asanoha: return "Asanoha"
        case .hexagons: return "Kikko"
        case .knot: return "Knot"
        case .waves: return "Waves"
        }
    }
}

enum ForkIconArt {
    static func image(_ kind: ForkIconKind, dark: Bool, size: CGFloat = 1024) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let g = NSGraphicsContext.current?.cgContext else { return false }
            draw(kind, dark: dark, in: g, size: size)
            return true
        }
    }

    private static func rgb(_ hex: Int) -> CGColor {
        CGColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// Drawn on a 1024 canvas, the plate where macOS puts an app's.
    static func draw(_ kind: ForkIconKind, dark: Bool, in g: CGContext, size: CGFloat) {
        g.saveGState()
        g.scaleBy(x: size / 1024, y: size / 1024)
        let ground = dark ? rgb(0x1F1E1C) : rgb(0xF7F2E7)
        let ink = dark ? rgb(0xDCC38C) : rgb(0xAE8E57)
        let plate = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
        g.saveGState()
        g.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: CGColor(gray: 0, alpha: 0.3))
        g.addPath(plate)
        g.setFillColor(ground)
        g.fillPath()
        g.restoreGState()
        g.addPath(plate)
        g.clip()
        g.translateBy(x: 512, y: 512)
        g.setStrokeColor(ink)
        g.setFillColor(ground)
        g.setLineCap(.round)
        g.setLineJoin(.round)
        switch kind {
        case .standard: break
        case .asanoha: asanoha(g)
        case .hexagons: hexagons(g)
        case .knot: knot(g, ground: ground, ink: ink)
        case .waves: waves(g)
        }
        g.restoreGState()
    }

    /// A hexagon about a point: a corner to the right, or with `pointy` up.
    private static func hexagon(_ centre: CGPoint, _ radius: CGFloat, pointy: Bool) -> CGPath {
        let path = CGMutablePath()
        for k in 0..<6 {
            let angle = (CGFloat(k) * 60 + (pointy ? 30 : 0)) * .pi / 180
            let point = CGPoint(x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle))
            if k == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    /// The hemp leaf's lines: a net of triangles, each with its middle
    /// joined to its corners.
    private static func leaves(_ g: CGContext, side s: CGFloat, reach: Int) {
        let h = s * sqrt(3) / 2
        func p(_ i: Int, _ j: Int) -> CGPoint { CGPoint(x: CGFloat(i) * s + CGFloat(j) * s / 2, y: CGFloat(j) * h) }
        for i in -reach...reach {
            for j in -reach...reach {
                for corners in [[p(i, j), p(i + 1, j), p(i, j + 1)], [p(i + 1, j), p(i + 1, j + 1), p(i, j + 1)]] {
                    let middle = CGPoint(x: (corners[0].x + corners[1].x + corners[2].x) / 3,
                                         y: (corners[0].y + corners[1].y + corners[2].y) / 3)
                    g.move(to: corners[0])
                    g.addLine(to: corners[1])
                    g.addLine(to: corners[2])
                    g.closePath()
                    for corner in corners {
                        g.move(to: middle)
                        g.addLine(to: corner)
                    }
                }
            }
        }
        g.strokePath()
    }

    private static func asanoha(_ g: CGContext) {
        let radius: CGFloat = 312
        g.saveGState()
        g.rotate(by: .pi / 2)
        g.addPath(hexagon(.zero, radius, pointy: false))
        g.clip()
        g.setLineWidth(7)
        leaves(g, side: radius / 3, reach: 8)
        g.restoreGState()
        g.setLineWidth(10)
        g.addPath(hexagon(.zero, radius, pointy: true))
        g.strokePath()
    }

    private static func hexagons(_ g: CGContext) {
        let r: CGFloat = 118
        var centres = [CGPoint.zero]
        for k in 0..<6 {
            let angle = CGFloat(k) * 60 * .pi / 180
            centres.append(CGPoint(x: r * sqrt(3) * cos(angle), y: r * sqrt(3) * sin(angle)))
        }
        g.saveGState()
        for centre in centres { g.addPath(hexagon(centre, r, pointy: true)) }
        g.clip()
        g.rotate(by: .pi / 2)
        g.setLineWidth(6)
        leaves(g, side: r, reach: 5)
        g.restoreGState()
        g.setLineWidth(9)
        for centre in centres {
            g.addPath(hexagon(centre, r, pointy: true))
            g.strokePath()
            g.addPath(hexagon(centre, r * 0.6, pointy: true))
            g.drawPath(using: .fillStroke)
        }
    }

    private static func knot(_ g: CGContext, ground: CGColor, ink: CGColor) {
        let radius: CGFloat = 132, away: CGFloat = 160, rope: CGFloat = 56
        func centre(_ k: Int) -> CGPoint {
            let angle = (90 + CGFloat(k) * 72) * .pi / 180
            return CGPoint(x: away * cos(angle), y: away * sin(angle) - 8)
        }
        func ring(_ at: CGPoint) {
            func circle(_ r: CGFloat) { g.addEllipse(in: CGRect(x: at.x - r, y: at.y - r, width: 2 * r, height: 2 * r)) }
            g.setStrokeColor(ground)
            g.setLineWidth(rope + 18)
            circle(radius)
            g.strokePath()
            g.setStrokeColor(ink)
            g.setLineWidth(rope)
            circle(radius)
            g.strokePath()
            // The rope's three strands.
            g.setStrokeColor(ground)
            g.setLineWidth(6)
            circle(radius - 9.5)
            circle(radius + 9.5)
            g.strokePath()
        }
        for k in 0..<5 { ring(centre(k)) }
        // The first ring over the last where they cross on the outside, so
        // each goes over one neighbour and under the other.
        let first = centre(0), last = centre(4)
        let middle = CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2)
        let half = hypot(first.x - last.x, first.y - last.y) / 2
        let out = sqrt(radius * radius - half * half)
        let knotCentre = CGPoint(x: 0, y: -8)
        let length = hypot(middle.x - knotCentre.x, middle.y - knotCentre.y)
        let crossing = CGPoint(x: middle.x + (middle.x - knotCentre.x) / length * out,
                               y: middle.y + (middle.y - knotCentre.y) / length * out)
        g.saveGState()
        g.addEllipse(in: CGRect(x: crossing.x - 62, y: crossing.y - 62, width: 124, height: 124))
        g.clip()
        ring(first)
        g.restoreGState()
    }

    private static func waves(_ g: CGContext) {
        let reach: CGFloat = 318, r: CGFloat = 112
        g.saveGState()
        g.addEllipse(in: CGRect(x: -reach, y: -reach, width: 2 * reach, height: 2 * reach))
        g.clip()
        g.setLineWidth(9)
        var row = 0
        var y = reach + r
        while y > -reach - 2 * r {
            var x = -reach - 2 * r + (row % 2 == 0 ? 0 : r)
            while x < reach + 2 * r {
                g.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                g.fillPath()
                for part in [0.96, 0.72, 0.48, 0.24] {
                    let ring = r * CGFloat(part)
                    g.addEllipse(in: CGRect(x: x - ring, y: y - ring, width: 2 * ring, height: 2 * ring))
                }
                g.strokePath()
                x += 2 * r
            }
            y -= r / 2
            row += 1
        }
        g.restoreGState()
    }
}
