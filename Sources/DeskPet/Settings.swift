import Foundation

enum Frequency: String, CaseIterable {
    case ultraOften
    case often
    case normal
    case rare

    var displayName: String {
        switch self {
        case .ultraOften: return "Ultra Often"
        case .often: return "Often"
        case .normal: return "Normal"
        case .rare: return "Rare"
        }
    }

    /// Range of seconds to wait *after a peek disappears* before the next
    /// one starts — not the same as time between one peek appearing and
    /// the next appearing, since a peek itself is on screen for ~4.5-6.25s
    /// (see PeekWindowController's slide/hold durations). At the slower
    /// bands that difference is invisible; at 5s it would double the felt
    /// cadence, which is why Ultra Often's gap is much shorter than its
    /// name's number would suggest — it's tuned for how often a peek
    /// actually shows up, roughly every 5-7s end to end.
    var delayRange: ClosedRange<Double> {
        switch self {
        case .ultraOften: return 1...1
        case .often: return 15...45
        case .normal: return 45...120
        case .rare: return 120...300
        }
    }
}

/// Thin UserDefaults-backed settings store. No external dependencies needed
/// for a menu-bar utility this small.
final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let enabled = "peek.enabled"
        static let frequency = "peek.frequency"
        static let disabledSpeciesIDs = "peek.disabledSpeciesIDs"
    }

    var enabled: Bool {
        get { defaults.object(forKey: Key.enabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    var frequency: Frequency {
        get { Frequency(rawValue: defaults.string(forKey: Key.frequency) ?? "") ?? .normal }
        set { defaults.set(newValue.rawValue, forKey: Key.frequency) }
    }

    /// All species are enabled by default; we persist the exclusions so a
    /// newly-added species is included automatically for existing users.
    private var disabledSpeciesIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.disabledSpeciesIDs) ?? []) }
        set { defaults.set(Array(newValue), forKey: Key.disabledSpeciesIDs) }
    }

    func isSpeciesEnabled(_ id: String) -> Bool {
        !disabledSpeciesIDs.contains(id)
    }

    func setSpecies(_ id: String, enabled: Bool) {
        var disabled = disabledSpeciesIDs
        if enabled {
            disabled.remove(id)
        } else {
            disabled.insert(id)
        }
        disabledSpeciesIDs = disabled
    }

    func setAllSpecies(enabled: Bool) {
        disabledSpeciesIDs = enabled ? [] : Set(Species.all.map(\.id))
    }

    var enabledSpecies: [Species] {
        Species.all.filter { isSpeciesEnabled($0.id) }
    }

    private init() {}
}
