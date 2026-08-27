import AppKit

/// Drives the "random times, random edge, random display" behavior,
/// rescheduling itself after every fire using a delay drawn from the
/// current frequency setting.
final class PeekScheduler {
    static let shared = PeekScheduler()

    /// Only ever one character on screen at a time — a second peek is
    /// skipped rather than queued, so a backlog can't build up after the
    /// machine wakes or the user leans on "Peek Now".
    private static let maxConcurrentPeeks = 1

    private var activeControllers: [ObjectIdentifier: PeekWindowController] = [:]
    private var pendingWorkItem: DispatchWorkItem?
    /// Set while an on-screen character is being sent away to make room
    /// for a "Peek Now" replacement.
    private var respawnAfterDismiss = false
    /// Avoids putting two peeks in a row on the same edge.
    private var lastEdge: PeekEdge?

    private init() {}

    func start() {
        scheduleNext()
    }

    /// Fires a peek immediately, without disturbing the regular schedule.
    /// If a character is already out, it's sent away first and the new one
    /// comes up somewhere else.
    func peekNow() {
        guard let current = activeControllers.values.first else {
            spawnPeek()
            return
        }
        respawnAfterDismiss = true
        current.dismissNow()
    }

    /// Re-draws the pending delay from the new frequency band so a change
    /// takes effect now instead of after the already-armed timer fires.
    func frequencyDidChange() {
        scheduleNext()
    }

    private func scheduleNext() {
        pendingWorkItem?.cancel()
        let delay = Double.random(in: Settings.shared.frequency.delayRange)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if Settings.shared.enabled {
                self.spawnPeek()
            }
            self.scheduleNext()
        }
        pendingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func spawnPeek() {
        guard activeControllers.count < Self.maxConcurrentPeeks else { return }
        // Lid closed or screen locked: nothing to animate for, so skip
        // this round rather than spend GPU/CPU on an unseen overlay.
        guard PowerAwareness.canPeek() else { return }
        // Re-read the screen list every time so newly attached displays
        // join the rotation and detached ones drop out.
        guard let screen = NSScreen.screens.randomElement() else { return }
        guard let species = speciesToShow() else { return }
        guard let edge = pickEdge() else { return }
        lastEdge = edge

        let controller = PeekWindowController()
        let id = ObjectIdentifier(controller)
        activeControllers[id] = controller

        controller.start(speciesID: species.id, edge: edge, screen: screen) { [weak self] in
            guard let self else { return }
            self.activeControllers.removeValue(forKey: id)
            if self.respawnAfterDismiss {
                self.respawnAfterDismiss = false
                self.spawnPeek()
            }
        }
    }

    /// Never the same edge twice running, so a new peek is visibly
    /// somewhere else than the one it replaced.
    private func pickEdge() -> PeekEdge? {
        let choices = PeekEdge.allCases.filter { $0 != lastEdge }
        return choices.randomElement() ?? PeekEdge.allCases.randomElement()
    }

    private func speciesToShow() -> Species? {
        let enabled = Settings.shared.enabledSpecies
        return enabled.isEmpty ? Species.all.randomElement() : enabled.randomElement()
    }
}
