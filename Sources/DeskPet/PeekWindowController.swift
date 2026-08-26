import AppKit
import SwiftUI

/// Hosts one peek: a transparent overlay pinned to a screen edge that
/// slides a character into view, has it flick an ear or wave a paw, then
/// slides back out and tears itself down.
///
/// Clicking the character makes it perform a gesture on the spot. Clicks
/// that land on the transparent parts of the panel are refused so they
/// fall through to whatever is underneath.
final class PeekWindowController: NSObject {
    private var panel: NSPanel?
    private var onFinished: (() -> Void)?
    private let state = PeekState()

    #if PEEK_DEV
    /// Seams used only by the development checks.
    var testPanel: NSPanel? { panel }
    var testLayout: PeekLayout? { layout }
    var testForcedGesture: Gesture?
    var testForcedFace: FaceVariant?
    var currentFace: FaceVariant { face }
    var currentReveal: CGFloat { state.reveal }
    private(set) var acceptedClicks = 0
    private(set) var playedGestures: [Gesture] = []
    #endif

    private var layout: PeekLayout?
    private var mask: AlphaMask?
    private var gestures: [Gesture] = []
    /// Chosen once when the peek starts and held for its whole life, so
    /// clicking never switches the character's expression mid-animation.
    private var face: FaceVariant = .plain
    private var isInteractive = false
    private var requestCounter = 0

    private var leaveWork: DispatchWorkItem?
    private var leanWork: DispatchWorkItem?
    private var gestureFrameCount = 0
    private var leaveDeadline = Date.distantPast
    private var finished = false

    private let slideInDuration: TimeInterval = 0.45
    /// Matches the view's reveal animation.
    private let leanDuration: TimeInterval = 0.45
    private let slideOutDuration: TimeInterval = 0.4
    /// One gesture runs ~1.4s, and ambient playback waits for the top of
    /// the idle loop (up to ~0.9s), so the character stays out long
    /// enough to actually perform it.
    private let holdRange: ClosedRange<Double> = 3.6...5.4
    /// Minimum time kept on screen after a click. A gesture runs ~1.8s,
    /// so this leaves margin for it to finish before the exit starts.
    private let postClickLinger: TimeInterval = 2.6

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func start(speciesID: String, edge: PeekEdge, screen: NSScreen, onFinished: @escaping () -> Void) {
        self.onFinished = onFinished

        let faces = SpriteLibrary.shared.availableFaces(for: speciesID)
        face = faces.randomElement() ?? .plain
        #if PEEK_DEV
        if let forced = testForcedFace { face = forced }
        #endif

        let idle = SpriteLibrary.shared.frames(for: speciesID, face: face)
        guard !idle.isEmpty else {
            finish()
            return
        }

        gestures = SpriteLibrary.shared.availableGestures(for: speciesID, face: face)
        var gestureArt: [Gesture: [NSImage]] = [:]
        for gesture in gestures {
            let art = SpriteLibrary.shared.frames(for: speciesID, face: face, gesture: gesture)
            gestureArt[gesture] = art
            gestureFrameCount = max(gestureFrameCount, art.count)
        }

        let layout = PeekLayoutBuilder.make(
            edge: edge,
            visibleFrame: screen.visibleFrame,
            naturalSize: SpriteLibrary.shared.naturalSize(for: speciesID, face: face)
        )
        self.layout = layout
        self.mask = SpriteLibrary.shared.hitMask(for: speciesID, face: face, edge: edge)

        #if PEEK_DEV
        state.onGestureStarted = { [weak self] gesture in
            self?.playedGestures.append(gesture)
        }
        #endif

        let panel = NSPanel(
            contentRect: layout.windowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        // Clicks are wanted, but only on the character itself — the
        // container view's hit test enforces that.
        panel.ignoresMouseEvents = false

        let container = PeekContainerView(frame: NSRect(origin: .zero, size: layout.windowFrame.size))
        container.hitTester = { [weak self] point in self?.isHit(at: point) ?? false }
        container.onClick = { [weak self] in self?.handleClick() }

        let hosting = NSHostingView(
            rootView: PeekContentView(
                idleFrames: idle,
                gestureFrames: gestureArt,
                layout: layout,
                state: state
            )
        )
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        panel.contentView = container
        self.panel = panel
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Let the initial hidden state render before animating in.
        DispatchQueue.main.async { [weak self] in
            self?.state.reveal = PeekLayoutBuilder.restRevealFraction
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + slideInDuration) { [weak self] in
            self?.isInteractive = true
        }

        scheduleLeave(after: slideInDuration + Double.random(in: holdRange))
    }

    // MARK: - Interaction

    /// `point` is in the container view's flipped, top-left-origin space.
    private func isHit(at point: NSPoint) -> Bool {
        guard isInteractive, let layout, let mask else { return false }
        return layout.hitsSprite(at: point, mask: mask, reveal: state.reveal)
    }

    private func handleClick() {
        guard isInteractive, !gestures.isEmpty else { return }
        #if PEEK_DEV
        acceptedClicks += 1
        #endif
        requestCounter += 1

        let gesture = pickGesture()
        let needed = gesture.requiredReveal

        // Ears show at rest, so they play straight away.
        guard needed > PeekLayoutBuilder.restRevealFraction + 0.001 else {
            state.request = GestureRequest(gesture: gesture, immediate: true, id: requestCounter)
            extendStay(by: postClickLinger)
            return
        }

        // A grin reaches past the chin and the arms are lower still, so
        // those gestures need the character further out. Two things
        // matter here:
        //
        // - The lean is set from this event handler rather than the view's
        //   gesture-start callback; mutating published state during a
        //   SwiftUI update isn't reliably applied.
        // - The gesture is held back until the lean finishes. Its largest
        //   movement lands in the first fifth of a second, which would
        //   otherwise happen while the moving part was still below the cut.
        state.reveal = needed

        let id = requestCounter
        leanWork?.cancel()
        DispatchQueue.main.asyncAfter(deadline: .now() + leanDuration) { [weak self] in
            guard let self, !self.finished else { return }
            self.state.request = GestureRequest(gesture: gesture, immediate: true, id: id)
        }

        let settleBack = leanDuration + gestureDuration + 0.2
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.finished else { return }
            self.state.reveal = PeekLayoutBuilder.restRevealFraction
        }
        leanWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + settleBack, execute: item)
        extendStay(by: settleBack + 0.4)
    }

    /// Picks evenly between kinds of motion rather than between sequences.
    /// The two ear flicks look nearly alike, so drawing uniformly across
    /// all four would show an ear half the time and read as "always the
    /// ear"; grouping them into one slot keeps the mix even.
    private func pickGesture() -> Gesture {
        #if PEEK_DEV
        if let forced = testForcedGesture {
            testForcedGesture = nil
            return forced
        }
        #endif
        let available = Gesture.families
            .map { $0.filter(gestures.contains) }
            .filter { !$0.isEmpty }
        guard let family = available.randomElement(), let pick = family.randomElement() else {
            return gestures.randomElement() ?? .earLeft
        }
        return pick
    }

    /// How long one gesture sequence takes to play through.
    private var gestureDuration: TimeInterval {
        Double(gestureFrameCount) * GesturePlayback.frameInterval
    }

    /// Sends this peek away now, ahead of its scheduled exit. Used when
    /// "Peek Now" replaces the character currently on screen.
    func dismissNow() {
        guard !finished else { return }
        leaveWork?.cancel()
        leanWork?.cancel()
        beginLeaving()
    }

    // MARK: - Lifecycle

    private func scheduleLeave(after delay: TimeInterval) {
        leaveWork?.cancel()
        leaveDeadline = Date().addingTimeInterval(delay)
        let item = DispatchWorkItem { [weak self] in self?.beginLeaving() }
        leaveWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Pushes the exit out to at least `interval` from now, never pulling
    /// it earlier than it was already going to be.
    private func extendStay(by interval: TimeInterval) {
        let target = Date().addingTimeInterval(interval)
        guard target > leaveDeadline else { return }
        scheduleLeave(after: interval)
    }

    private func beginLeaving() {
        guard !finished else { return }
        isInteractive = false
        state.reveal = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + slideOutDuration) { [weak self] in
            self?.finish()
        }
    }

    /// A display being added, removed, or rearranged can leave this panel
    /// stranded off-screen, so bail out rather than linger.
    @objc private func screenParametersChanged() {
        guard let panel, let layout else { return }
        let stillValid = NSScreen.screens.contains { $0.visibleFrame.intersects(layout.windowFrame) }
        if !stillValid || panel.screen == nil {
            finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        isInteractive = false
        leaveWork?.cancel()
        leaveWork = nil
        leanWork?.cancel()
        leanWork = nil
        NotificationCenter.default.removeObserver(self)
        panel?.orderOut(nil)
        panel = nil
        onFinished?()
        onFinished = nil
    }
}

/// Content view that refuses clicks outside the character's own pixels,
/// letting them fall through to the app underneath.
private final class PeekContainerView: NSView {
    var hitTester: ((NSPoint) -> Bool)?
    var onClick: (() -> Void)?

    /// Matches SwiftUI's top-left origin so layout rects need no flipping.
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard hitTester?(local) == true else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
