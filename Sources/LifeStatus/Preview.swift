import AppKit
import LifeStatusCore

/// Runs without opening the menu bar, writing user data, or registering a login item.
func renderPreviews(to directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let catalog = CopyCatalog(directory: directory.appendingPathComponent("unused-config"), writesAllowed: false)
    var state = HealthState(now: Date()); state.streak = 7; state.onboardingComplete = true
    let levels = Levels(hp: 72, water: 24, san: 46)
    func save(_ view: NSView, name: String, dark: Bool) throws {
        let window = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = view; view.appearance = window.appearance
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
        window.contentView = nil
    }
    for dark in [false, true] {
        let suffix = dark ? "dark" : "light"
        let panel = InstrumentView()
        panel.update(levels: levels, state: state, copy: catalog.message("water", advance: false), streakTip: catalog.streakDescription(state))
        try save(panel, name: "panel-\(suffix).png", dark: dark)
        try save(WelcomeView(copy: catalog.content.onboarding), name: "welcome-\(suffix).png", dark: dark)
        var broken = state; broken.failedToday = true
        panel.update(levels: levels, state: broken, copy: catalog.message("water", advance: false), streakTip: "")
        try save(panel, name: "interrupted-\(suffix).png", dark: dark)
        let gaugeButton = panel.subviews.compactMap { $0 as? PaddleButton }.first!
        var pressed = false; panel.onReplenish = { _ in pressed = true }; gaugeButton.performClick(nil)
        precondition(pressed, "Paddle must invoke its action")
        precondition(panel.subviews.compactMap { $0 as? FlameView }.first!.isHidden, "Interrupted streak must be hidden")
    }
    for theme in ["normal", "hp", "water", "san", "empty", "happy"] {
        let image = Artwork.menuImage(theme: theme, value: 24)
        precondition(image.isTemplate && image.size == NSSize(width: 18, height: 18))
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("menu-\(theme).png"))
    }
    let animationPanel = InstrumentView()
    animationPanel.update(levels: Levels(hp: 70, water: 0, san: 50), state: state, copy: "爱你老己", streakTip: "")
    let row = animationPanel.subviews.compactMap { $0 as? GaugeView }.first { $0.gauge == .water }!
    animationPanel.update(levels: Levels(hp: 70, water: 100 / 3, san: 50), state: state, copy: "爱你老己", streakTip: "", replenished: .water)
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        precondition(row.amount == 0, "Refill must start from the visible value")
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        precondition(row.amount > 0 && row.amount < 4, "Refill must have intermediate frames")
        let intermediate = row.amount
        animationPanel.update(levels: Levels(hp: 70, water: 200 / 3, san: 50), state: state, copy: "爱你老己", streakTip: "", replenished: .water)
        precondition(row.amount == intermediate, "Rapid clicks must continue without jumping")
        RunLoop.main.run(until: Date().addingTimeInterval(0.85))
        precondition(row.amount == 7)
        precondition(animationPanel.subviews.compactMap { $0 as? PaddleButton }.allSatisfy { $0.travel == 0 })
    } else { precondition(row.amount == 4, "Reduced motion must update immediately") }
    print("Native previews rendered; copy, paddles, refill continuity, hidden streak and template icons checked.")
}
