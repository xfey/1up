import AppKit
import LifeStatusCore

class FlippedView: NSView {
    override var isFlipped: Bool { true }
    var palette: Palette { Palette(dark: effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua) }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true; subviews.forEach { $0.needsDisplay = true } }
}

final class GaugeView: FlippedView {
    let gauge: Gauge
    var amount: Double = 10 { didSet { if amount != oldValue { needsDisplay = true } } }
    var infusing = false
    init(gauge: Gauge, frame: NSRect) {
        self.gauge = gauge; super.init(frame: frame)
        toolTip = "\(gauge.label) · \(gauge.action)"
        setAccessibilityElement(true); setAccessibilityRole(.progressIndicator); setAccessibilityLabel("\(gauge.label)状态")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        Artwork.gauge(gauge, at: CGPoint(x: 0, y: 6))
        for index in 0..<10 {
            let rect = NSRect(x: 24 + CGFloat(index) * 12, y: 10, width: 9, height: 9)
            fill(rect, NSColor(hex: 0x2b332e))
            let fraction = min(1, max(0, amount - Double(index)))
            if fraction > 0 {
                let accent = Palette.accent(gauge)
                fill(NSRect(x: rect.minX, y: rect.minY, width: 9 * fraction, height: 9), infusing && fraction < 1 ? accent.blended(withFraction: 0.2, of: .white)! : accent)
            }
        }
    }
}

final class PaddleButton: NSButton {
    var travel: CGFloat = 0 { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let palette = Palette(dark: effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        gradient(bounds.insetBy(dx: 0.5, dy: 0.5), NSColor.black.withAlphaComponent(0.15), NSColor.white.withAlphaComponent(0.03), radius: 5)
        stroke(bounds.insetBy(dx: 0.5, dy: 0.5), NSColor.black.withAlphaComponent(0.24), radius: 5)
        fill(NSRect(x: 12, y: 4, width: 4, height: 17), palette.keyEdge, radius: 2)
        let grip = NSRect(x: 4, y: 5 + travel, width: 20, height: 10)
        fill(grip.offsetBy(dx: 0, dy: 2), palette.keyEdge, radius: 3)
        gradient(grip, palette.keyTop, palette.keyBottom, radius: 3)
        stroke(grip.insetBy(dx: 0.5, dy: 0.5), NSColor.black.withAlphaComponent(0.2), radius: 3)
        for y in 0..<4 { fill(NSRect(x: 7, y: grip.minY + 3 + CGFloat(y), width: 14, height: 1), y % 2 == 0 ? .black.withAlphaComponent(0.18) : .white.withAlphaComponent(0.18)) }
        if window?.firstResponder === self { stroke(bounds.insetBy(dx: 1.5, dy: 1.5), .keyboardFocusIndicatorColor, radius: 4) }
    }
}

final class FlameView: FlippedView {
    var active = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) { Artwork.drawFlame(at: CGPoint(x: 8, y: 7), active: active, palette: palette) }
}

final class InstrumentView: FlippedView {
    var onReplenish: ((Gauge) -> Void)?
    private var rows: [Gauge: GaugeView] = [:]
    private var paddles: [Gauge: PaddleButton] = [:]
    private let message = NSTextField(labelWithString: "")
    private let flame = FlameView(frame: NSRect(x: 168, y: 100, width: 28, height: 27))
    private struct Infusion { let from: Double; let target: Double; let start: Double; let duration: Double }
    private var infusions: [Gauge: Infusion] = [:]
    private var paddleStarts: [Gauge: (time: Double, from: CGFloat)] = [:]
    private var animationTimer: Timer?
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 205, height: 128))
        for (index, gauge) in Gauge.allCases.enumerated() {
            let row = GaugeView(gauge: gauge, frame: NSRect(x: 15, y: 12 + index * 28, width: 141, height: 28))
            rows[gauge] = row; addSubview(row)
            let paddle = PaddleButton(frame: NSRect(x: 168, y: 13.5 + Double(index) * 28, width: 28, height: 25))
            paddle.isBordered = false; paddle.title = ""; paddle.setButtonType(.momentaryPushIn)
            paddle.target = self; paddle.action = #selector(replenish(_:)); paddle.tag = index
            paddle.toolTip = gauge.action; paddle.setAccessibilityLabel(gauge.action)
            paddles[gauge] = paddle; addSubview(paddle)
        }
        message.frame = NSRect(x: 15, y: 106.5, width: 147, height: 14)
        message.font = .systemFont(ofSize: 10); message.lineBreakMode = .byTruncatingTail
        message.maximumNumberOfLines = 1; message.cell?.usesSingleLineMode = true
        addSubview(message); addSubview(flame)
        flame.setAccessibilityElement(true); flame.setAccessibilityRole(.image)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { animationTimer?.invalidate() }
    override func draw(_ dirtyRect: NSRect) {
        chassis(bounds, palette: palette)
        screen(NSRect(x: 9, y: 8, width: 153, height: 92))
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); message.textColor = palette.ink }
    @objc private func replenish(_ sender: NSButton) { onReplenish?(Gauge.allCases[sender.tag]) }
    func update(levels: Levels, state: HealthState, copy: String, streakTip: String, replenished: Gauge? = nil, resetAnimations: Bool = false) {
        if resetAnimations { stopAnimations() }
        let now = ProcessInfo.processInfo.systemUptime
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for gauge in Gauge.allCases {
            let row = rows[gauge]!, target = levels[gauge] / 10
            row.setAccessibilityValue("\(Int(levels[gauge].rounded()))%")
            if replenished == gauge && !reduced && target > row.amount {
                infusions[gauge] = Infusion(from: row.amount, target: target, start: now, duration: 0.48 + min(6, target - row.amount) * 0.04)
            } else if infusions[gauge] == nil { row.amount = target }
            if replenished == gauge && !reduced { paddleStarts[gauge] = (now, paddles[gauge]!.travel) }
        }
        if !infusions.isEmpty || !paddleStarts.isEmpty { startAnimations() }
        message.stringValue = copy; message.toolTip = copy; message.textColor = palette.ink
        flame.isHidden = state.failedToday
        flame.setAccessibilityElement(!state.failedToday)
        flame.active = state.streak > 0; flame.toolTip = state.failedToday ? nil : streakTip
        flame.setAccessibilityLabel(state.failedToday ? nil : streakTip)
    }
    func stopAnimations() {
        for (gauge, infusion) in infusions { rows[gauge]?.amount = infusion.target; rows[gauge]?.infusing = false }
        infusions.removeAll(); paddleStarts.removeAll()
        paddles.values.forEach { $0.travel = 0 }
        animationTimer?.invalidate(); animationTimer = nil
    }
    private func startAnimations() {
        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in self?.animate() }
        RunLoop.main.add(timer, forMode: .common); animationTimer = timer
    }
    private func animate() {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { stopAnimations(); return }
        let now = ProcessInfo.processInfo.systemUptime
        for (gauge, job) in infusions {
            let progress = min(1, max(0, (now - job.start) / job.duration))
            rows[gauge]?.amount = job.from + (job.target - job.from) * (1 - pow(1 - progress, 3))
            rows[gauge]?.infusing = progress < 1
            if progress >= 1 { infusions.removeValue(forKey: gauge) }
        }
        for (gauge, job) in paddleStarts {
            let progress = min(1, max(0, (now - job.time) / 0.44))
            if progress >= 1 { paddles[gauge]?.travel = 0; paddleStarts.removeValue(forKey: gauge); continue }
            let stops: [(Double, CGFloat)] = [(0, job.from), (0.2, 6), (0.3, 6), (0.7, -1), (0.85, 0.5), (1, 0)]
            let index = stops.firstIndex { $0.0 > progress }!
            let from = stops[index - 1], to = stops[index]
            let eased = 1 - pow(1 - (progress - from.0) / (to.0 - from.0), 3)
            paddles[gauge]?.travel = from.1 + (to.1 - from.1) * eased
        }
        if infusions.isEmpty && paddleStarts.isEmpty { animationTimer?.invalidate(); animationTimer = nil }
    }
}

final class StartButton: NSButton {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let palette = Palette(dark: effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        gradient(bounds.insetBy(dx: 0.5, dy: 0.5), palette.keyTop, palette.keyBottom, radius: 4)
        stroke(bounds.insetBy(dx: 0.5, dy: 0.5), palette.keyEdge, radius: 4)
        text(title, rect: NSRect(x: 0, y: 6, width: bounds.width, height: 16), size: 11, color: palette.ink, weight: .semibold, alignment: .center)
        if window?.firstResponder === self { stroke(bounds.insetBy(dx: 1.5, dy: 1.5), .keyboardFocusIndicatorColor, radius: 3) }
    }
}

final class WelcomeView: FlippedView {
    let copy: CopyContent.Onboarding
    let login = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let start = StartButton(frame: NSRect(x: 11, y: 176, width: 226, height: 28))
    var onStart: ((Bool) -> Void)?
    init(copy: CopyContent.Onboarding) {
        self.copy = copy
        super.init(frame: NSRect(x: 0, y: 0, width: 248, height: 215))
        login.title = copy.launchAtLogin; login.font = .systemFont(ofSize: 11)
        login.frame = NSRect(x: 11, y: 149, width: 226, height: 18); login.state = .on; addSubview(login)
        start.title = copy.start; start.isBordered = false; start.target = self; start.action = #selector(begin)
        start.keyEquivalent = "\r"; addSubview(start)
        setAccessibilityElement(true); setAccessibilityRole(.group)
        setAccessibilityLabel(copy.title + "。" + Gauge.allCases.compactMap { copy.actions[$0.rawValue] }.joined(separator: "。"))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func begin() { onStart?(login.state == .on) }
    override func draw(_ dirtyRect: NSRect) {
        chassis(bounds, palette: palette)
        text(copy.title, rect: NSRect(x: 11, y: 11, width: 199, height: 21), size: 14, color: palette.ink, weight: .semibold)
        Artwork.face(at: CGPoint(x: 219, y: 12), color: palette.ink)
        screen(NSRect(x: 11, y: 40, width: 226, height: 100))
        for (index, gauge) in Gauge.allCases.enumerated() {
            let y = CGFloat(45 + index * 30)
            Artwork.gauge(gauge, at: CGPoint(x: 20, y: y + 7))
            text(gauge.label, rect: NSRect(x: 43, y: y + 8, width: 27, height: 16), size: 10, color: Palette.accent(gauge))
            text(copy.actions[gauge.rawValue] ?? "", rect: NSRect(x: 77, y: y + 7, width: 151, height: 17), size: 11, color: NSColor(hex: 0xd5ddd1))
        }
    }
}
