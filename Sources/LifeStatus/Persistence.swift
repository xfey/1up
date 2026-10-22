import Foundation
import JavaScriptCore
import LifeStatusCore
import OSLog

let appLog = Logger(subsystem: "com.xfey.LifeStatus", category: "app")

final class StateStore {
    let directory: URL
    private var lastSaved: Data?
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LifeStatus", isDirectory: true)
    }
    func load(now: Date) -> HealthState {
        let url = directory.appendingPathComponent("state.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return HealthState(now: now) }
        do {
            let data = try Data(contentsOf: url)
            let state = try JSONDecoder().decode(HealthState.self, from: data)
            guard state.isValid else { throw CocoaError(.fileReadCorruptFile) }
            return state
        } catch {
            appLog.error("State could not be read; preserving a recovery copy: \(error.localizedDescription)")
            let backup = directory.appendingPathComponent("state-recovery-\(Int(now.timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: url, to: backup)
            return HealthState(now: now)
        }
    }
    func save(_ state: HealthState) {
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            guard data != lastSaved else { return }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent("state.json"), options: .atomic)
            lastSaved = data
        } catch { appLog.error("State could not be saved: \(error.localizedDescription)") }
    }
}

struct CopyContent: Codable {
    var messages: [String: [String]]
    var onboarding: Onboarding
    var streak: [String: String]
    struct Onboarding: Codable {
        var title: String
        var actions: [String: String]
        var launchAtLogin: String
        var start: String
    }
    var isValid: Bool {
        ["normal", "hp", "water", "san", "empty", "happy"].allSatisfy {
            guard let lines = messages[$0] else { return false }
            return !lines.isEmpty && lines.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        } && [onboarding.title, onboarding.launchAtLogin, onboarding.start].allSatisfy { !$0.isEmpty }
        && Gauge.allCases.allSatisfy { !(onboarding.actions[$0.rawValue] ?? "").isEmpty }
        && ["unlit", "active"].allSatisfy { !(streak[$0] ?? "").isEmpty }
    }

    /// Old editable copy files keep their content on disk; correct the two
    /// retired names when displaying them without replacing other custom copy.
    var withCurrentTheoryNames: CopyContent {
        func correct(_ text: String) -> String {
            text.replacingOccurrences(of: "一起加入薄肌计划&大水计划", with: "一起实践薄肌理论&大水理论")
                .replacingOccurrences(of: "马上执行薄肌计划", with: "马上实践薄肌理论")
                .replacingOccurrences(of: "马上执行大水计划", with: "马上实践大水理论")
                .replacingOccurrences(of: "薄肌计划", with: "薄肌理论")
                .replacingOccurrences(of: "大水计划", with: "大水理论")
        }
        var updated = self
        updated.messages = messages.mapValues { $0.map(correct) }
        updated.onboarding.title = correct(onboarding.title)
        updated.onboarding.actions = onboarding.actions.mapValues(correct)
        updated.onboarding.launchAtLogin = correct(onboarding.launchAtLogin)
        updated.onboarding.start = correct(onboarding.start)
        updated.streak = streak.mapValues(correct)
        return updated
    }
}

final class CopyCatalog {
    let url: URL
    private let bundled: CopyContent
    private(set) var content: CopyContent
    private var indices: [String: Int] = [:]
    init(directory: URL, writesAllowed: Bool = true) {
        url = directory.appendingPathComponent("copy.json")
        let context = JSContext()!
        context.evaluateScript("var window = {};")
        let resources: Bundle
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let url = Bundle.main.resourceURL?.appendingPathComponent("LifeStatus_LifeStatus.bundle"), let bundle = Bundle(url: url) else {
                fatalError("The application is missing its bundled copy resources.")
            }
            resources = bundle
        } else { resources = Bundle.module }
        for name in ["microcopy", "onboarding", "streak"] {
            if let path = resources.url(forResource: name, withExtension: "js", subdirectory: "config"), let source = try? String(contentsOf: path, encoding: .utf8) {
                context.evaluateScript(source)
            }
        }
        let json = context.evaluateScript("JSON.stringify({messages: window.LifeStatusCopyConfig, onboarding: window.LifeStatusOnboardingConfig, streak: window.LifeStatusStreakConfig})")?.toString()
        guard let data = json?.data(using: .utf8), let decoded = try? JSONDecoder().decode(CopyContent.self, from: data), decoded.isValid else {
            fatalError("Bundled copy configuration is invalid. Check config/*.js before building.")
        }
        bundled = decoded; content = decoded
        if writesAllowed && !FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                try encoder.encode(decoded).write(to: url, options: .atomic)
            } catch { appLog.error("Copy file could not be created: \(error.localizedDescription)") }
        }
        reload()
    }
    func reload() {
        guard let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(CopyContent.self, from: data), decoded.isValid else { content = bundled; return }
        content = decoded.withCurrentTheoryNames
    }
    func message(_ theme: String, advance: Bool) -> String {
        let lines = Array(NSOrderedSet(array: content.messages[theme] ?? content.messages["normal"]!).array as! [String])
        let index = indices[theme].map { advance ? ($0 + 1) % lines.count : $0 % lines.count } ?? 0
        indices[theme] = index
        return lines[index]
    }
    func streakDescription(_ state: HealthState) -> String {
        guard !state.failedToday else { return "" }
        return (content.streak[state.streak > 0 ? "active" : "unlit"] ?? "").replacingOccurrences(of: "{days}", with: String(state.streak))
    }
}
