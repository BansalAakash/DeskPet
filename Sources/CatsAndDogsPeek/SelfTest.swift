// Development-only checks. Compiled out of the shipping app; build with
//   swift build -Xswiftc -DPEEK_DEV
// (or Scripts/run_tests.sh) to include them.
#if PEEK_DEV
import AppKit

/// Geometry/asset assertions, run via `PEEK_SELFTEST=1`. Kept in the
/// binary because the layout math is pure and worth re-checking after
/// any change to edge handling or display assumptions.
enum SelfTest {
    static func run() -> Never {
        var failures: [String] = []

        func check(_ condition: Bool, _ message: @autoclosure () -> String) {
            if !condition { failures.append(message()) }
        }

        // Simulated displays, including a secondary one placed above the
        // primary — the arrangement that broke the old off-screen-window
        // approach — and a small low-res one.
        let displays: [(name: String, visible: CGRect)] = [
            ("primary", CGRect(x: 0, y: 0, width: 1440, height: 875)),
            ("above-primary", CGRect(x: 200, y: 900, width: 1920, height: 1080)),
            ("left-negative", CGRect(x: -1680, y: -200, width: 1680, height: 1050)),
            ("tiny", CGRect(x: 0, y: 0, width: 320, height: 240))
        ]

        for species in Species.all {
          let faces = SpriteLibrary.shared.availableFaces(for: species.id)
          check(
            Set(faces) == Set(FaceVariant.allCases),
            "\(species.id): missing faces \(Set(FaceVariant.allCases).subtracting(faces))"
          )
          for face in faces {
            let tagBase = "\(species.id)/\(face.rawValue)"
            let idle = SpriteLibrary.shared.frames(for: species.id, face: face)
            check(!idle.isEmpty, "\(tagBase): no idle frames loaded")

            let natural = SpriteLibrary.shared.naturalSize(for: species.id, face: face)
            check(natural.width > 0 && natural.height > 0, "\(tagBase): bad natural size \(natural)")

            for gesture in Gesture.allCases {
                check(
                    gesture.requiredReveal <= PeekLayoutBuilder.maxRevealFraction + 0.001,
                    "\(gesture.rawValue): needs reveal \(gesture.requiredReveal) but the window only reaches \(PeekLayoutBuilder.maxRevealFraction)"
                )
            }

            // The characters grin permanently, and the tongue hangs below
            // the chin. If the resting reveal doesn't clear it, every peek
            // shows a tongue sliced off mid-way.
            for (i, frame) in idle.enumerated() {
                guard let grin = grinExtent(frame) else { continue }
                check(
                    grin < PeekLayoutBuilder.restRevealFraction,
                    "\(tagBase) idle f\(i): face reaches \(String(format: "%.3f", grin)) but only \(PeekLayoutBuilder.restRevealFraction) shows at rest — it would be clipped"
                )
            }

            // --- gesture assets ---
            let available = SpriteLibrary.shared.availableGestures(for: species.id, face: face)
            check(
                Set(available) == Set(Gesture.allCases),
                "\(tagBase): missing gestures \(Set(Gesture.allCases).subtracting(available))"
            )
            for gesture in available {
                let seq = SpriteLibrary.shared.frames(for: species.id, face: face, gesture: gesture)
                check(seq.count >= 4, "\(tagBase)/\(gesture.rawValue): only \(seq.count) frames")
                // Every gesture frame must match the idle art's dimensions,
                // otherwise cutting between them would visibly jump.
                if let idle0 = idle.first {
                    for (i, f) in seq.enumerated() {
                        check(
                            f.size == idle0.size,
                            "\(tagBase)/\(gesture.rawValue) f\(i): size \(f.size) != idle \(idle0.size)"
                        )
                    }
                }
                // Playback cuts in and out only at the idle loop's first
                // frame, so the sequence has to start and end on that pose.
                if let idle0 = idle.first, let first = seq.first, let last = seq.last {
                    check(pixelsMatch(idle0, first), "\(tagBase)/\(gesture.rawValue): first frame != idle pose")
                    check(pixelsMatch(idle0, last), "\(tagBase)/\(gesture.rawValue): last frame != idle pose")
                }
                // The middle of the sequence must actually differ, or the
                // gesture would be a no-op.
                if let idle0 = idle.first, seq.count > 2 {
                    let mid = seq[seq.count / 4]
                    check(!pixelsMatch(idle0, mid), "\(tagBase)/\(gesture.rawValue): mid frame identical to idle")

                    // A gesture is pointless if the part it moves sits
                    // outside the revealed strip. The visible portion runs
                    // from the head end (0) down to the reveal fraction, so
                    // the moving pixels must start above that cut. This is
                    // what made paw waves invisible: the arms sit ~70% down
                    // the art, past the 0.6 resting cut, so the character
                    // now leans out to 0.8 for them.
                    if let moved = changedRowRange(idle0, mid) {
                        let revealUsed = gesture.requiredReveal
                        check(
                            moved.lowerBound < revealUsed,
                            "\(tagBase)/\(gesture.rawValue): moves art at \(String(format: "%.2f", moved.lowerBound))–\(String(format: "%.2f", moved.upperBound)) but only \(revealUsed) is revealed — the motion would be off screen"
                        )
                    } else {
                        check(false, "\(tagBase)/\(gesture.rawValue): could not locate moved pixels")
                    }
                }
            }

            for edge in PeekEdge.allCases {
                for display in displays {
                    let layout = PeekLayoutBuilder.make(
                        edge: edge,
                        visibleFrame: display.visible,
                        naturalSize: natural
                    )
                    let tag = "\(tagBase)/\(edge)/\(display.name)"
                    let win = layout.windowFrame

                    // 1. The panel must sit entirely inside the visible
                    //    area, so nothing relies on off-screen clipping
                    //    and nothing hides under the menu bar or Dock.
                    if display.visible.width >= win.width && display.visible.height >= win.height {
                        check(
                            display.visible.contains(win),
                            "\(tag): window \(win) escapes visible frame \(display.visible)"
                        )
                    }

                    // 2. The panel must actually touch the edge it peeks from.
                    let epsilon: CGFloat = 0.5
                    switch edge {
                    case .bottom: check(abs(win.minY - display.visible.minY) < epsilon, "\(tag): not flush to bottom")
                    case .top:    check(abs(win.maxY - display.visible.maxY) < epsilon, "\(tag): not flush to top")
                    case .left:   check(abs(win.minX - display.visible.minX) < epsilon, "\(tag): not flush to left")
                    case .right:  check(abs(win.maxX - display.visible.maxX) < epsilon, "\(tag): not flush to right")
                    }

                    // 3. The window is sized for the deepest lean, and
                    //    spans the character's full length along the edge.
                    let full = layout.fullSpriteSize
                    let maxReveal = PeekLayoutBuilder.maxRevealFraction
                    switch edge {
                    case .top, .bottom:
                        check(abs(win.height / full.height - maxReveal) < 0.01, "\(tag): window reveal \(win.height / full.height)")
                        check(abs(win.width - full.width) < epsilon, "\(tag): width != full width")
                    case .left, .right:
                        check(abs(win.width / full.width - maxReveal) < 0.01, "\(tag): window reveal \(win.width / full.width)")
                        check(abs(win.height - full.height) < epsilon, "\(tag): height != full height")
                    }

                    // 4. Reveal offsets: hidden must fully evacuate the
                    //    window, resting must sit back from the edge, and
                    //    leaning out must fill it.
                    let axis: CGFloat = (edge == .top || edge == .bottom) ? full.height : full.width
                    func magnitude(_ s: CGSize) -> CGFloat {
                        (edge == .top || edge == .bottom) ? abs(s.height) : abs(s.width)
                    }
                    let hidden = magnitude(layout.offset(forReveal: 0))
                    let rest = magnitude(layout.offset(forReveal: PeekLayoutBuilder.restRevealFraction))
                    let leaning = magnitude(layout.offset(forReveal: maxReveal))
                    check(abs(hidden - win.size.widthOrHeight(edge)) < epsilon, "\(tag): hidden offset \(hidden) != window \(win.size.widthOrHeight(edge))")
                    check(leaning < epsilon, "\(tag): leaning offset should be zero, got \(leaning)")
                    check(rest > epsilon && rest < hidden, "\(tag): rest offset \(rest) not between leaning and hidden")
                    // Resting shows exactly restRevealFraction of the art.
                    let restVisible = (axis * maxReveal - rest) / axis
                    check(
                        abs(restVisible - PeekLayoutBuilder.restRevealFraction) < 0.01,
                        "\(tag): resting shows \(restVisible), expected \(PeekLayoutBuilder.restRevealFraction)"
                    )

                    // 5. Click routing: the character's visible middle must
                    //    accept clicks so tapping it triggers a gesture,
                    //    while the transparent margin must fall through to
                    //    the app underneath.
                    guard let mask = SpriteLibrary.shared.hitMask(for: species.id, face: face, edge: edge) else {
                        failures.append("\(tag): hit mask missing")
                        continue
                    }
                    let clip = layout.spriteClipRect
                    let restReveal = PeekLayoutBuilder.restRevealFraction
                    // Sweep the window rather than guessing where the head
                    // lands for each rotation: a decent share of it must be
                    // clickable at rest, and the outer corners must not be.
                    var hits = 0, probes = 0
                    for i in 0..<24 {
                        for j in 0..<24 {
                            let p = CGPoint(
                                x: clip.minX + clip.width * (CGFloat(i) + 0.5) / 24,
                                y: clip.minY + clip.height * (CGFloat(j) + 0.5) / 24
                            )
                            probes += 1
                            if layout.hitsSprite(at: p, mask: mask, reveal: restReveal) { hits += 1 }
                        }
                    }
                    check(hits > probes / 12, "\(tag): only \(hits)/\(probes) points clickable at rest")
                    check(
                        !layout.hitsSprite(at: CGPoint(x: clip.midX, y: clip.midY - 5000), mask: mask, reveal: restReveal),
                        "\(tag): click far outside the window was captured"
                    )
                    let corners = [
                        CGPoint(x: clip.minX + 0.5, y: clip.minY + 0.5),
                        CGPoint(x: clip.maxX - 0.5, y: clip.minY + 0.5),
                        CGPoint(x: clip.minX + 0.5, y: clip.maxY - 0.5),
                        CGPoint(x: clip.maxX - 0.5, y: clip.maxY - 0.5)
                    ]
                    for corner in corners {
                        check(
                            !layout.hitsSprite(at: corner, mask: mask, reveal: restReveal),
                            "\(tag): transparent corner \(corner) swallowed a click"
                        )
                    }
                }
            }
          }
        }

        if failures.isEmpty {
            let size = SpriteLibrary.shared.naturalSize(for: Species.all[0].id, face: .plain)
            print("SELFTEST PASS (\(Species.all.count) species x \(FaceVariant.allCases.count) faces x \(PeekEdge.allCases.count) edges x \(displays.count) displays, \(Gesture.allCases.count) gestures; on-screen \(Int(size.width))x\(Int(size.height))pt)")
            exit(0)
        } else {
            print("SELFTEST FAIL — \(failures.count) issue(s):")
            failures.forEach { print("  - \($0)") }
            exit(1)
        }
    }

    /// Compares decoded pixels rather than encoded bytes — the gesture
    /// frames are re-encoded by the generator, so file bytes differ even
    /// where the image is identical.
    private static func pixelsMatch(_ a: NSImage, _ b: NSImage, tolerance: Int = 2) -> Bool {
        guard let pa = rgbaBytes(a), let pb = rgbaBytes(b), pa.count == pb.count else { return false }
        var differing = 0
        for i in stride(from: 0, to: pa.count, by: 4) {
            if abs(Int(pa[i + 3]) - Int(pb[i + 3])) > 8 ||
               abs(Int(pa[i]) - Int(pb[i])) > 8 {
                differing += 1
                if differing > tolerance { return false }
            }
        }
        return true
    }

    /// Vertical span of pixels that differ between two frames, as
    /// fractions of the art's height (0 = head end). Used to check a
    /// gesture's motion falls inside the revealed strip.
    private static func changedRowRange(_ a: NSImage, _ b: NSImage) -> ClosedRange<CGFloat>? {
        guard let cgA = a.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let pa = rgbaBytes(a), let pb = rgbaBytes(b), pa.count == pb.count
        else { return nil }
        let width = cgA.width, height = cgA.height
        var minRow = Int.max, maxRow = Int.min
        for y in 0..<height {
            let row = y * width * 4
            for x in 0..<width {
                let i = row + x * 4
                if abs(Int(pa[i + 3]) - Int(pb[i + 3])) > 24 ||
                   abs(Int(pa[i]) - Int(pb[i])) > 24 {
                    minRow = min(minRow, y)
                    maxRow = max(maxRow, y)
                    break
                }
            }
        }
        guard minRow <= maxRow else { return nil }
        return (CGFloat(minRow) / CGFloat(height))...(CGFloat(maxRow) / CGFloat(height))
    }

    /// Lowest row the pink nose/tongue reaches, as a fraction of the art's
    /// height. Rows need a few pink pixels to count — the art has the odd
    /// isolated pixel that happens to match.
    private static func grinExtent(_ image: NSImage, minRun: Int = 3) -> CGFloat? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let px = rgbaBytes(image)
        else { return nil }
        let w = cg.width, h = cg.height
        var lowest: Int?
        for y in 0..<h {
            var count = 0
            for x in 0..<w {
                let i = (y * w + x) * 4
                if px[i + 3] > 200, px[i] > 200, px[i + 1] < 170, px[i + 2] > 110 {
                    count += 1
                    if count >= minRun { lowest = y; break }
                }
            }
        }
        guard let lowest else { return nil }
        return CGFloat(lowest) / CGFloat(h)
    }

    private static func rgbaBytes(_ image: NSImage) -> [UInt8]? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = cg.width, h = cg.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = buf.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? buf : nil
    }
}

/// Live click check, run via `PEEK_TEST_CLICK=1`. Unlike `SelfTest` this
/// needs a running app, because it delivers real mouse events through
/// AppKit to prove clicking the character triggers a gesture — and that
/// clicking its transparent margin still falls through to the app below.
final class ClickSelfTest {
    private var controller: PeekWindowController?

    func run() {
        setvbuf(stdout, nil, _IONBF, 0)
        guard let screen = NSScreen.screens.first else { return }

        let controller = PeekWindowController()
        self.controller = controller
        controller.start(speciesID: "cat", edge: .bottom, screen: screen) { }

        var failures = 0

        // Sit untouched for a while first: gestures must only ever come
        // from a click, never on their own.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self, let layout = controller.testLayout else { return }
            let clip = layout.spriteClipRect
            let centre = CGPoint(x: clip.midX, y: clip.midY)

            let faceAtStart = controller.currentFace
            let quiet = controller.playedGestures.isEmpty
            print("  no gesture without a click: \(quiet ? "OK" : "<-- FAIL, played \(controller.playedGestures.map(\.rawValue))")")
            failures += quiet ? 0 : 1

            failures += self.send(centre, label: "click on transparent corner is refused",
                                  expectAccept: false, at: CGPoint(x: clip.minX + 1, y: clip.minY + 1))

            // --- ear: plays at once, no lean ---
            controller.testForcedGesture = .earLeft
            let restBefore = controller.currentReveal
            failures += self.send(centre, label: "ear click", expectAccept: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) {
                let playedEar = controller.playedGestures.contains(.earLeft)
                print("  ear gesture played: \(playedEar ? "OK" : "<-- FAIL")")
                failures += playedEar ? 0 : 1
                let noLean = abs(controller.currentReveal - restBefore) < 0.001
                print("  ear does not lean out: \(noLean ? "OK" : "<-- FAIL (\(controller.currentReveal))")")
                failures += noLean ? 0 : 1

                // --- paw: leans out first, then waves ---
                controller.testForcedGesture = .paw
                failures += self.send(centre, label: "paw click", expectAccept: true)
                let leaned = controller.currentReveal
                let leanOK = leaned > restBefore + 0.01
                print("  paw leans out: \(restBefore) -> \(leaned) \(leanOK ? "OK" : "<-- FAIL")")
                failures += leanOK ? 0 : 1

                // The wave must wait for the lean, then actually play.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    let playedPaw = controller.playedGestures.contains(.paw)
                    print("  paw gesture played after lean: \(playedPaw ? "OK" : "<-- FAIL")")
                    failures += playedPaw ? 0 : 1

                    // With the arm on screen, the moving part must sit
                    // inside the visible strip.
                    let armFraction: CGFloat = 0.75
                    let visible = controller.currentReveal
                    let armOK = visible > armFraction
                    print("  arm within revealed strip: reveal \(visible) > \(armFraction) \(armOK ? "OK" : "<-- FAIL")")
                    failures += armOK ? 0 : 1

                    let faceHeld = controller.currentFace == faceAtStart
                    print("  face unchanged by clicking: \(faceAtStart.rawValue) \(faceHeld ? "OK" : "<-- FAIL, now \(controller.currentFace.rawValue)")")
                    failures += faceHeld ? 0 : 1

                    print(failures == 0
                          ? "CLICKTEST PASS (face \(faceAtStart.rawValue), played \(controller.playedGestures.map(\.rawValue)))"
                          : "CLICKTEST FAIL (\(failures) issue(s))")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exit(failures == 0 ? 0 : 1) }
                }
            }
        }
    }

    /// Returns 1 if the outcome didn't match expectation, else 0.
    /// `at` overrides where the click lands (defaults to `point`).
    private func send(_ point: CGPoint, label: String, expectAccept: Bool, at: CGPoint? = nil) -> Int {
        guard let controller, let panel = controller.testPanel else {
            print("  \(label): no panel  <-- FAIL")
            return 1
        }
        let target = at ?? point
        // The container view is flipped (top-left origin); NSEvent wants
        // window coordinates (bottom-left).
        let windowPoint = NSPoint(x: target.x, y: panel.frame.height - target.y)
        let before = controller.acceptedClicks
        guard let event = NSEvent.mouseEvent(
            with: .leftMouseDown, location: windowPoint, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        ) else {
            print("  \(label): could not build event  <-- FAIL")
            return 1
        }
        panel.sendEvent(event)
        let accepted = controller.acceptedClicks > before
        let ok = accepted == expectAccept
        print("  \(label): accepted=\(accepted) expected=\(expectAccept) \(ok ? "OK" : "<-- FAIL")")
        return ok ? 0 : 1
    }
}

/// Checks that "Peek Now" replaces whatever is on screen with a fresh
/// peek somewhere else, run via `PEEK_TEST_PEEKNOW=1`.
enum PeekNowSelfTest {
    static func run() {
        setvbuf(stdout, nil, _IONBF, 0)
        var failures = 0

        func visiblePanels() -> [NSPanel] {
            NSApp.windows.compactMap { $0 as? NSPanel }.filter { $0.isVisible }
        }

        PeekScheduler.shared.peekNow()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let first = visiblePanels()
            guard let firstFrame = first.first?.frame else {
                print("  first peek appeared: <-- FAIL (none visible)")
                exit(1)
            }
            print("  first peek appeared: OK at \(firstFrame.origin)")
            print("  exactly one on screen: \(first.count == 1 ? "OK" : "<-- FAIL (\(first.count))")")
            failures += first.count == 1 ? 0 : 1

            // Replace it.
            PeekScheduler.shared.peekNow()

            // Mid-transition there must still never be two characters out.
            var maxSeen = 0
            for i in 0..<12 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.1) {
                    maxSeen = max(maxSeen, visiblePanels().count)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                let second = visiblePanels()
                guard let secondFrame = second.first?.frame else {
                    print("  replacement appeared: <-- FAIL (none visible)")
                    exit(1)
                }
                print("  replacement appeared: OK at \(secondFrame.origin)")
                print("  never more than one at a time: max=\(maxSeen) \(maxSeen <= 1 ? "OK" : "<-- FAIL")")
                failures += maxSeen <= 1 ? 0 : 1
                let moved = secondFrame.origin != firstFrame.origin
                print("  came up somewhere else: \(moved ? "OK" : "<-- FAIL (same spot)")")
                failures += moved ? 0 : 1
                print(failures == 0 ? "PEEKNOW PASS" : "PEEKNOW FAIL (\(failures) issue(s))")
                exit(failures == 0 ? 0 : 1)
            }
        }
    }
}


/// Tallies which face peeks actually come up wearing, via
/// `PEEK_TEST_FACES=1`. The mix should be even.
enum FaceTallySelfTest {
    static func run() {
        setvbuf(stdout, nil, _IONBF, 0)
        guard let screen = NSScreen.screens.first else { exit(1) }

        // What the library thinks it has.
        for species in Species.all {
            let faces = SpriteLibrary.shared.availableFaces(for: species.id)
            print("  \(species.id) available faces: \(faces.map(\.rawValue))")
            for face in faces {
                let n = SpriteLibrary.shared.frames(for: species.id, face: face).count
                print("     \(face.rawValue): \(n) idle frames")
            }
        }

        // What actually gets picked, and whether the peek survives.
        var tally: [String: Int] = [:]
        var vanished = 0
        var controllers: [PeekWindowController] = []
        let runs = 400
        for _ in 0..<runs {
            let c = PeekWindowController()
            controllers.append(c)
            var finished = false
            c.start(speciesID: Species.all.randomElement()!.id,
                    edge: .bottom, screen: screen) { finished = true }
            tally[c.currentFace.rawValue, default: 0] += 1
            // A peek whose art failed to load tears itself down at once.
            if finished { vanished += 1 }
            c.dismissNow()
        }
        print("  over \(runs) peeks: \(tally.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
        print("  peeks that died immediately (missing art): \(vanished)")
        exit(0)
    }
}

#endif
