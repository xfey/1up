import AppKit
import LifeStatusCore

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }
}

struct Palette {
    let dark: Bool
    var metalTop: NSColor { NSColor(hex: dark ? 0x373b3c : 0xdedfda) }
    var metal: NSColor { NSColor(hex: dark ? 0x2d3132 : 0xd0d3ce) }
    var metalBottom: NSColor { NSColor(hex: dark ? 0x282c2d : 0xc1c6bf) }
    var edge: NSColor { NSColor(hex: dark ? 0x191e1d : 0x9ea69e) }
    var ink: NSColor { NSColor(hex: dark ? 0xc9d0c7 : 0x4e574f) }
    var keyTop: NSColor { NSColor(hex: dark ? 0x484f4d : 0xe6e9e1) }
    var keyBottom: NSColor { NSColor(hex: dark ? 0x353c39 : 0xcdd2c8) }
    var keyEdge: NSColor { NSColor(hex: dark ? 0x1a211d : 0x99a394) }
    var flame: NSColor { NSColor(hex: dark ? 0xd69a62 : 0xad6336) }
    var core: NSColor { NSColor(hex: dark ? 0xf4db9e : 0xf6d68c) }
    var quiet: NSColor { NSColor(hex: dark ? 0x8e998b : 0x71796f) }
    static func accent(_ gauge: Gauge) -> NSColor {
        NSColor(hex: gauge == .hp ? 0xd99078 : gauge == .water ? 0x88b6c2 : 0x9dbe8b)
    }
}

func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius) }
func fill(_ rect: NSRect, _ color: NSColor, radius: CGFloat = 0) { color.setFill(); rounded(rect, radius).fill() }
func stroke(_ rect: NSRect, _ color: NSColor, radius: CGFloat = 0) { color.setStroke(); let path = rounded(rect, radius); path.lineWidth = 1; path.stroke() }
func gradient(_ rect: NSRect, _ top: NSColor, _ bottom: NSColor, radius: CGFloat = 0, angle: CGFloat = 90) {
    NSGradient(starting: top, ending: bottom)?.draw(in: rounded(rect, radius), angle: angle)
}
func text(_ value: String, rect: NSRect, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular, alignment: NSTextAlignment = .left) {
    let style = NSMutableParagraphStyle(); style.alignment = alignment; style.lineBreakMode = .byTruncatingTail
    (value as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style])
}

func chassis(_ rect: NSRect, palette: Palette) {
    gradient(rect.insetBy(dx: 0.5, dy: 0.5), palette.metalTop, palette.metalBottom, radius: 9, angle: 55)
    stroke(rect.insetBy(dx: 0.5, dy: 0.5), NSColor.black.withAlphaComponent(0.22), radius: 9)
    stroke(rect.insetBy(dx: 1.5, dy: 1.5), NSColor.white.withAlphaComponent(palette.dark ? 0.07 : 0.25), radius: 8)
}
func screen(_ rect: NSRect) {
    gradient(rect, NSColor(hex: 0x1a211e), NSColor(hex: 0x111714), radius: 5, angle: 55)
    stroke(rect.insetBy(dx: 0.5, dy: 0.5), NSColor.black.withAlphaComponent(0.45), radius: 5)
}

func pixels(_ rows: [String], at origin: CGPoint, color: NSColor, scale: CGFloat = 1) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current?.shouldAntialias = false
    color.setFill()
    for (y, row) in rows.enumerated() {
        for (x, bit) in row.enumerated() where bit == "1" {
            NSRect(x: origin.x + CGFloat(x) * scale, y: origin.y + CGFloat(y) * scale, width: scale, height: scale).fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
}

enum Artwork {
    static let gauges: [Gauge: [String]] = [
        .hp: ["001100001100", "011110011110", "111111111111", "111111111111", "111111111111", "011111111110", "001111111100", "000111111000", "000011110000", "000001100000"],
        .water: ["011111111000", "010000001000", "010000001110", "010000001010", "010000001010", "010000001010", "010000001110", "010111101000", "010111101000", "010111101000", "001111110000"],
        .san: ["0000000000000000", "0000000000111100", "0000000001111100", "0111100011111100", "0111110011111000", "0011111011110000", "0001111111100000", "0000011110000000", "0000001100000000", "0000001100000000", "0000001100000000", "0000001100000000", "0000001100000000", "0000000000000000", "0000000000000000", "0000000000000000"]
    ]
    static let symbols: [String: [String]] = [
        "hp": ["0000110000", "0000110000", "0100000010", "0011111100", "0000110000", "0000110000", "0001001000", "0010000100"],
        "san": ["0000001110", "0110011110", "0111111100", "0011111000", "0000110000", "0000110000", "0000110000", "0000110000"],
        "normal": ["1100001100", "1100001100", "0000000000", "0000000000", "0100001000", "0011110000"],
        "empty": ["0000000000", "1100001100", "0000000000", "0000000000", "0011110000"],
        "happy": ["0100001000", "1010010100", "0000000000", "0000000000", "0100001000", "0011110000"],
        "water": ["1111111000", "1000001110", "1000001010", "1000001010", "1000001110", "1000001000", "1000001000", "0111110000"]
    ]
    static let flame = ["000000100000", "000001100000", "000011100000", "000011110000", "000111110100", "000111111100", "001111211110", "001112211110", "001122221110", "000122221100", "000112211100", "000011111000", "000000000000"]
    static func gauge(_ gauge: Gauge, at point: CGPoint) {
        let rows = gauges[gauge]!
        pixels(rows, at: CGPoint(x: point.x + floor(CGFloat(16 - rows[0].count) / 2), y: point.y + floor(CGFloat(16 - rows.count) / 2)), color: Palette.accent(gauge))
    }
    static func face(at point: CGPoint, color: NSColor) {
        for rect in [NSRect(x: 3, y: 2, width: 12, height: 1), NSRect(x: 2, y: 3, width: 1, height: 12), NSRect(x: 15, y: 3, width: 1, height: 12), NSRect(x: 3, y: 15, width: 12, height: 1)] {
            fill(rect.offsetBy(dx: point.x, dy: point.y), color)
        }
        pixels(symbols["normal"]!, at: CGPoint(x: point.x + 5, y: point.y + 6), color: color)
    }
    static func menuImage(theme: String, value: Double = 0) -> NSImage {
        let remaining = max(0, min(100, value))
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let halo = Gauge(rawValue: theme) != nil
            if halo {
                if remaining > 0, let ctx = NSGraphicsContext.current?.cgContext {
                    ctx.setStrokeColor(NSColor.black.cgColor); ctx.setLineWidth(1.3)
                    ctx.addArc(center: CGPoint(x: 9, y: 9), radius: 7.75, startAngle: -.pi / 2, endAngle: -.pi / 2 + .pi * 2 * remaining / 100, clockwise: false)
                    ctx.strokePath()
                }
            } else {
                for rect in [NSRect(x: 3, y: 2, width: 12, height: 1), NSRect(x: 2, y: 3, width: 1, height: 12), NSRect(x: 15, y: 3, width: 1, height: 12), NSRect(x: 3, y: 15, width: 12, height: 1)] { fill(rect, .black) }
            }
            pixels(symbols[theme] ?? symbols["normal"]!, at: CGPoint(x: halo ? 4 : 5, y: halo ? 5 : 6), color: .black)
            if theme == "water", remaining > 0 {
                let height = max(1, ceil(remaining / 25))
                fill(NSRect(x: 6, y: 11 - height, width: 3, height: height), .black)
            }
            return true
        }
        image.isTemplate = true
        return image
    }
    static func drawFlame(at point: CGPoint, active: Bool, palette: Palette) {
        let rows = flame.map(Array.init)
        func occupied(_ x: Int, _ y: Int) -> Bool { y >= 0 && y < rows.count && x >= 0 && x < rows[y].count && rows[y][x] != "0" }
        for (y, row) in rows.enumerated() {
            for (x, cell) in row.enumerated() where cell != "0" {
                if !active && occupied(x - 1, y) && occupied(x + 1, y) && occupied(x, y - 1) && occupied(x, y + 1) { continue }
                fill(NSRect(x: point.x + CGFloat(x), y: point.y + CGFloat(y), width: 1, height: 1), active ? (cell == "2" ? palette.core : palette.flame) : palette.quiet)
            }
        }
    }
}
