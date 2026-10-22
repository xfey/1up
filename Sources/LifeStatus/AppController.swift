import AppKit
import CoreGraphics
import ServiceManagement
import LifeStatusCore

final class StatusPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store: StateStore
    private let smokeDirectory: URL?
    private var tracker: ActivityTracker!
    private var catalog: CopyCatalog!
    private var statusItem: NSStatusItem!
    private let instrument = InstrumentView()
    private var welcome: WelcomeView?
    private let panel = StatusPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var ticker: Timer?
    private var outsideMonitor: Any?
    private var localMonitor: Any?
    private var restReasons: Set<String> = []
    private var theme = "normal"
    private var feedbackUntil: TimeInterval = 0
    private var feedbackJob: DispatchWorkItem?
    private var lastImageKey = ""
    private var lastSavedUptime: TimeInterval = 0
    private var opened = false

    init(smokeDirectory: URL? = nil) {
        self.smokeDirectory = smokeDirectory
        self.store = StateStore(directory: smokeDirectory?.appendingPathComponent("data"))
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if smokeDirectory == nil, let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil); return
        }
        let now = Date(), uptime = ProcessInfo.processInfo.systemUptime
        tracker = ActivityTracker(state: store.load(now: now), now: now, uptime: uptime)
        catalog = CopyCatalog(directory: store.directory)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .popUpMenu; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.delegate = self; panel.onEscape = { [weak self] in self?.closePanel() }
        instrument.onReplenish = { [weak self] gauge in self?.replenish(gauge) }
        statusItem = NSStatusBar.system.statusItem(withLength: 30)
        statusItem.button?.target = self; statusItem.button?.action = #selector(statusClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.setAccessibilityLabel("\(AppIdentity.name)，展开健康状态；右键显示菜单")
        installObservers(); configureTimer(); refresh(resetAnimations: true)
        if !tracker.state.onboardingComplete { showPanel() }
        if smokeDirectory != nil { DispatchQueue.main.async { self.runSmokeCheck() } }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if tracker != nil { sample(); store.save(tracker.state) }
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        ticker?.invalidate(); feedbackJob?.cancel(); removeMonitors()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }
    private func configureTimer() {
        ticker?.invalidate()
        let timer = Timer(timeInterval: opened ? 1 : 5, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        timer.tolerance = opened ? 0.1 : 1
        RunLoop.main.add(timer, forMode: .common); ticker = timer
    }
    @objc private func tick() {
        sample(); refresh()
        let uptime = ProcessInfo.processInfo.systemUptime
        if uptime - lastSavedUptime >= 30 { store.save(tracker.state); lastSavedUptime = uptime }
    }
    private func sample() {
        guard tracker.state.onboardingComplete else { return }
        let before = tracker.state
        tracker.sample(now: Date(), uptime: ProcessInfo.processInfo.systemUptime,
                       idle: CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~UInt32(0))!))
        if before.day != tracker.state.day || before.failedToday != tracker.state.failedToday { store.save(tracker.state) }
    }
    private func interaction() {
        guard tracker.state.onboardingComplete else { return }
        tracker.interact(now: Date(), uptime: ProcessInfo.processInfo.systemUptime)
    }
    @objc private func statusClicked(_ sender: Any?) {
        interaction()
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true { showMenu(); return }
        opened ? closePanel() : showPanel()
    }
    private func showPanel() {
        catalog.reload(); interaction()
        let view: NSView
        if tracker.state.onboardingComplete { view = instrument }
        else {
            let card = WelcomeView(copy: catalog.content.onboarding)
            card.onStart = { [weak self] enabled in self?.start(loginEnabled: enabled) }
            welcome = card; view = card
        }
        panel.setContentSize(tracker.state.onboardingComplete ? NSSize(width: 205, height: 128) : NSSize(width: 248, height: 215))
        panel.contentView = view
        positionPanel()
        opened = true; configureTimer(); refresh(advanceCopy: true)
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
    }
    private func positionPanel() {
        guard let button = statusItem.button, let barWindow = button.window else { return }
        let anchor = barWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screenFrame = (barWindow.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = max(screenFrame.minX + 6, min(anchor.midX - panel.frame.width / 2, screenFrame.maxX - panel.frame.width - 6))
        let y = max(screenFrame.minY + 6, min(anchor.minY - panel.frame.height - 5, screenFrame.maxY - panel.frame.height - 5))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
    private func closePanel() {
        panel.orderOut(nil); opened = false; instrument.stopAnimations()
        removeMonitors(); configureTimer(); store.save(tracker.state)
    }
    func windowDidResignKey(_ notification: Notification) { if opened { closePanel() } }
    private func installMonitors() {
        removeMonitors()
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.closePanel() }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown && event.keyCode == 53 { self.closePanel(); return nil }
            if event.type != .keyDown && event.window !== self.panel && event.window !== self.statusItem.button?.window { self.closePanel() }
            return event
        }
    }
    private func removeMonitors() {
        if let monitor = outsideMonitor { NSEvent.removeMonitor(monitor) }; outsideMonitor = nil
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }; localMonitor = nil
    }
    private func refresh(advanceCopy: Bool = false, replenished: Gauge? = nil, resetAnimations: Bool = false) {
        let uptime = ProcessInfo.processInfo.systemUptime
        let levels = tracker.state.onboardingComplete ? tracker.visibleLevels : Levels()
        theme = levels.theme(current: theme)
        let displayTheme = uptime < feedbackUntil ? "happy" : theme
        let value = Gauge(rawValue: displayTheme).map { levels[$0] } ?? 0
        let key = "\(displayTheme)-\(Int(value * 10))"
        if key != lastImageKey { statusItem.button?.image = Artwork.menuImage(theme: displayTheme, value: value); lastImageKey = key }
        let detail = Gauge(rawValue: theme).map { "\($0.label)剩余 \(Int(levels[$0]))% · \($0.action)" } ?? (theme == "empty" ? "三槽全空，休息一下吧" : "状态良好")
        statusItem.button?.toolTip = "\(AppIdentity.name) · \(detail)\n左键展开 · 右键菜单"
        statusItem.button?.setAccessibilityValue(detail)
        if opened {
            let copy = catalog.message(displayTheme, advance: advanceCopy)
            instrument.update(levels: levels, state: tracker.state, copy: copy, streakTip: catalog.streakDescription(tracker.state), replenished: replenished, resetAnimations: resetAnimations)
        }
    }
    private func replenish(_ gauge: Gauge) {
        tracker.replenish(gauge, now: Date(), uptime: ProcessInfo.processInfo.systemUptime)
        feedbackUntil = ProcessInfo.processInfo.systemUptime + Rules.feedbackDuration
        feedbackJob?.cancel()
        let job = DispatchWorkItem { [weak self] in self?.refresh() }
        feedbackJob = job; DispatchQueue.main.asyncAfter(deadline: .now() + Rules.feedbackDuration, execute: job)
        refresh(advanceCopy: true, replenished: gauge); store.save(tracker.state)
    }
    private func start(loginEnabled: Bool) {
        tracker.completeOnboarding(now: Date(), uptime: ProcessInfo.processInfo.systemUptime)
        store.save(tracker.state)
        panel.setContentSize(NSSize(width: 205, height: 128)); panel.contentView = instrument; positionPanel()
        refresh(resetAnimations: true)
        setLogin(enabled: loginEnabled)
    }
    private func installObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspace.addObserver(self, selector: #selector(suspend(_:)), name: name, object: nil)
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspace.addObserver(self, selector: #selector(resume(_:)), name: name, object: nil)
        }
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(suspend(_:)), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(resume(_:)), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
        for name in [NSNotification.Name.NSSystemTimeZoneDidChange, NSNotification.Name.NSCalendarDayChanged, NSNotification.Name("NSSystemClockDidChangeNotification")] {
            NotificationCenter.default.addObserver(self, selector: #selector(tick), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }
    private func reason(_ name: NSNotification.Name) -> String {
        if name == NSWorkspace.willSleepNotification || name == NSWorkspace.didWakeNotification { return "sleep" }
        if name == NSWorkspace.sessionDidResignActiveNotification || name == NSWorkspace.sessionDidBecomeActiveNotification { return "session" }
        return "lock"
    }
    @objc private func suspend(_ note: Notification) {
        sample(); restReasons.insert(reason(note.name))
        tracker.suspend(now: Date(), uptime: ProcessInfo.processInfo.systemUptime)
        feedbackUntil = 0; feedbackJob?.cancel()
        if opened { closePanel() }
        refresh(resetAnimations: true); store.save(tracker.state)
    }
    @objc private func resume(_ note: Notification) {
        restReasons.remove(reason(note.name))
        if restReasons.isEmpty { tracker.resume(now: Date(), uptime: ProcessInfo.processInfo.systemUptime); refresh(resetAnimations: true); store.save(tracker.state) }
    }
    @objc private func screenChanged() { if opened { positionPanel() } }
    private func showMenu() {
        if opened { closePanel() }
        let menu = NSMenu()
        let status = SMAppService.mainApp.status
        let login = NSMenuItem(title: status == .requiresApproval ? "登录启动：等待系统允许…" : "登录后自动启动", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self; login.state = status == .enabled ? .on : status == .requiresApproval ? .mixed : .off
        menu.addItem(login)
        let edit = NSMenuItem(title: "编辑文案…", action: #selector(editCopy), keyEquivalent: ""); edit.target = self; menu.addItem(edit)
        menu.addItem(.separator())
        let about = NSMenuItem(title: "关于 \(AppIdentity.name)", action: #selector(about), keyEquivalent: ""); about.target = self; menu.addItem(about)
        let quit = NSMenuItem(title: "退出 \(AppIdentity.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); quit.target = NSApp; menu.addItem(quit)
        if let button = statusItem.button { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button) }
    }
    @objc private func toggleLogin() {
        if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        else { setLogin(enabled: SMAppService.mainApp.status != .enabled) }
    }
    private func setLogin(enabled: Bool) {
        do {
            let status = SMAppService.mainApp.status
            if enabled && (status == .notRegistered || status == .notFound) { try SMAppService.mainApp.register() }
            else if !enabled && (status == .enabled || status == .requiresApproval) { try SMAppService.mainApp.unregister() }
        } catch {
            appLog.error("Login item update failed: \(error.localizedDescription)")
            let alert = NSAlert(); alert.messageText = "登录启动未能更新"
            alert.informativeText = "应用仍可正常使用。请将 \(AppIdentity.name) 放入“应用程序”后，从菜单栏右键菜单重试。\n\(error.localizedDescription)"
            alert.addButton(withTitle: "知道了"); alert.runModal()
        }
    }
    @objc private func editCopy() { NSWorkspace.shared.open(catalog.url) }
    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        catalog.reload()
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: AppIdentity.name, .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0", .credits: NSAttributedString(string: "起身 · 喝水 · 远眺\n" + catalog.content.onboarding.title)])
    }

    private func runSmokeCheck() {
        precondition(panel.contentView?.frame.size == NSSize(width: 248, height: 215))
        precondition(opened && panel.isVisible)
        precondition(statusItem.button?.image?.isTemplate == true)
        tracker.completeOnboarding(now: Date(), uptime: ProcessInfo.processInfo.systemUptime)
        closePanel(); showPanel()
        precondition(panel.contentView === instrument && instrument.frame.size == NSSize(width: 205, height: 128))
        let firstMessage = instrument.subviews.compactMap { $0 as? NSTextField }.first!.stringValue
        closePanel(); showPanel()
        let secondMessage = instrument.subviews.compactMap { $0 as? NSTextField }.first!.stringValue
        precondition(firstMessage != secondMessage)
        replenish(.water)
        precondition(tracker.state.levels.water == 100)
        suspend(Notification(name: NSNotification.Name("com.apple.screenIsLocked")))
        precondition(!opened && tracker.state.levels == Levels())
        resume(Notification(name: NSNotification.Name("com.apple.screenIsUnlocked")))
        store.save(tracker.state)
        precondition(store.load(now: Date()).onboardingComplete)
        print("Native lifecycle smoke passed: welcome, panel size, open/close copy rotation, refill, lock/unlock, persistence. Login items untouched.")
        NSApp.terminate(nil)
    }
}
