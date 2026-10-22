import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
if let index = CommandLine.arguments.firstIndex(of: "--render-previews"), CommandLine.arguments.count > index + 1 {
    app.finishLaunching()
    do {
        try renderPreviews(to: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true))
        exit(0)
    } catch {
        fputs("Preview failed: \(error)\n", stderr)
        exit(1)
    }
}
let smokeIndex = CommandLine.arguments.firstIndex(of: "--smoke-test")
let smokeDirectory = smokeIndex.flatMap { index in CommandLine.arguments.count > index + 1 ? URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true) : nil }
let controller = AppController(smokeDirectory: smokeDirectory)
app.delegate = controller
app.run()
