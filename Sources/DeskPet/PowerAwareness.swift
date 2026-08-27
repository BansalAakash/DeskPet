import AppKit
import IOKit

/// Whether conditions right now make a peek worth showing at all. Checked
/// once before every spawn so the app never wakes up the GPU to animate
/// on a screen nobody can see.
///
/// System sleep already stops everything for free — a suspended process
/// doesn't fire timers. This covers the case that doesn't: clamshell mode,
/// where a charger and an external display keep the Mac fully awake with
/// the lid shut. Screen lock gets the same treatment for the same reason.
enum PowerAwareness {
    static func canPeek() -> Bool {
        !NSScreen.screens.isEmpty && !isLidClosed() && !isScreenLocked()
    }

    /// Reads the lid switch straight from IOPMrootDomain — the same
    /// property System Settings itself reads. There's no public
    /// notification for lid changes, so this is polled on demand (right
    /// before a spawn, at most once every few seconds to a few minutes)
    /// rather than watched continuously.
    private static func isLidClosed() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return (value?.takeRetainedValue() as? Bool) ?? false
    }

    private static func isScreenLocked() -> Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return info["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
