import AppKit

// Headless test modes run before any GUI comes up
let arguments = CommandLine.arguments
if arguments.count >= 2, arguments[1].hasPrefix("--") {
    runHeadless(args: arguments)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()
