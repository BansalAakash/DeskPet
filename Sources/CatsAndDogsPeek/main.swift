import AppKit

#if PEEK_DEV
if ProcessInfo.processInfo.environment["PEEK_SELFTEST"] != nil {
    SelfTest.run()
}
#endif

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
