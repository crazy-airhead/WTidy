import AppKit

// NSApplication.delegate 为 unowned 引用，用全局常量保活
let appDelegate = AppDelegate()

let app = NSApplication.shared
app.delegate = appDelegate
app.run()
