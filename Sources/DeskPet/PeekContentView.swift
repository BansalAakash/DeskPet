import SwiftUI

/// Drives one peek's presentation. Owned by the window controller and
/// observed by the view, so the controller can trigger the slide and
/// request gestures without touching the window's frame.
/// A request for the character to perform a gesture.
struct GestureRequest: Equatable {
    let gesture: Gesture
    /// Clicks play at once so the tap feels answered. Ambient gestures
    /// wait for the top of the idle loop, where the pose lines up exactly
    /// with the gesture's first frame.
    let immediate: Bool
    /// Distinguishes repeat requests for the same gesture.
    let id: Int
}

final class PeekState: ObservableObject {
    /// How much of the character shows, as a fraction of its length.
    /// 0 tucks it away; the controller raises it to lean out for a wave.
    @Published var reveal: CGFloat = 0
    /// Set to ask for a gesture; the view consumes and clears it.
    @Published var request: GestureRequest?
}

/// Renders a character clipped to a strip flush against the screen edge,
/// sliding it in and out by animating an offset *inside* that strip.
///
/// The window itself never moves or resizes and stays wholly on-screen,
/// so how much of the character shows can't be thrown off by another
/// display sitting beyond the edge.
struct PeekContentView: View {
    let idleFrames: [NSImage]
    let gestureFrames: [Gesture: [NSImage]]
    let layout: PeekLayout
    @ObservedObject var state: PeekState

    @State private var frameIndex = 0
    @State private var playing: Gesture?
    @State private var gestureIndex = 0

    private let frameInterval = GesturePlayback.frameInterval

    private var edge: PeekEdge { layout.anchoredEdge }

    private var currentFrame: NSImage {
        if let playing, let seq = gestureFrames[playing], gestureIndex < seq.count {
            return seq[gestureIndex]
        }
        guard !idleFrames.isEmpty else { return NSImage() }
        return idleFrames[frameIndex % idleFrames.count]
    }

    /// Which side of the clip strip the character's head is pinned to.
    private var spriteAlignment: Alignment {
        switch edge {
        case .bottom: return .top
        case .top: return .bottom
        case .left: return .trailing
        case .right: return .leading
        }
    }

    var body: some View {
        Image(nsImage: currentFrame)
            .resizable()
            .interpolation(.high)
            .frame(width: layout.naturalSpriteSize.width, height: layout.naturalSpriteSize.height)
            .rotationEffect(.degrees(PeekOrientation.rotationDegrees(for: edge)))
            .scaleEffect(x: 1, y: PeekOrientation.isVerticallyFlipped(for: edge) ? -1 : 1)
            // Give the rotated content a layout box matching its new
            // bounding size; rotationEffect alone doesn't resize it.
            .frame(width: layout.fullSpriteSize.width, height: layout.fullSpriteSize.height)
            .offset(layout.offset(forReveal: state.reveal))
            .animation(.easeOut(duration: 0.45), value: state.reveal)
            .frame(
                width: layout.spriteClipRect.width,
                height: layout.spriteClipRect.height,
                alignment: spriteAlignment
            )
            .clipped()
            .onReceive(Timer.publish(every: frameInterval, on: .main, in: .common).autoconnect()) { _ in
                advance()
            }
    }

    private func advance() {
        if let current = playing {
            gestureIndex += 1
            let count = gestureFrames[current]?.count ?? 0
            if gestureIndex >= count {
                // The gesture's last frame is the idle pose, so dropping
                // back to idle frame 0 continues without a jump.
                playing = nil
                gestureIndex = 0
                frameIndex = 0
                // A click during the gesture is honoured as soon as it ends.
                startRequestedGesture()
            }
            return
        }

        if startRequestedGesture(requireImmediate: true) { return }

        guard !idleFrames.isEmpty else { return }
        frameIndex = (frameIndex + 1) % idleFrames.count

        // Ambient gestures only cut in at the top of the idle loop, where
        // the pose matches the gesture's first frame exactly.
        if frameIndex == 0 {
            _ = startRequestedGesture()
        }
    }

    /// Consumes a pending request if it's eligible. Returns whether one started.
    @discardableResult
    private func startRequestedGesture(requireImmediate: Bool = false) -> Bool {
        guard let request = state.request else { return false }
        if requireImmediate && !request.immediate { return false }
        guard let seq = gestureFrames[request.gesture], !seq.isEmpty else {
            state.request = nil
            return false
        }
        playing = request.gesture
        gestureIndex = 0
        state.request = nil
        return true
    }
}

enum GesturePlayback {
    /// ~11 fps, matching the pace of the source idle loop.
    static let frameInterval = 0.09
}
