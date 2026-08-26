import CoreGraphics
import Foundation

// MARK: - Orientation

/// How a species' upright source art is turned so the character's head
/// pokes *into* the screen from a given edge.
enum PeekOrientation {
    /// Bounding box after orienting `natural` art for `edge` — width and
    /// height swap for the side edges, which are rotated 90°.
    static func boundingSize(natural: CGSize, edge: PeekEdge) -> CGSize {
        switch edge {
        case .top, .bottom:
            return natural
        case .left, .right:
            return CGSize(width: natural.height, height: natural.width)
        }
    }

    /// Rotation in SwiftUI's convention (positive = clockwise).
    static func rotationDegrees(for edge: PeekEdge) -> Double {
        switch edge {
        case .top, .bottom: return 0
        case .left: return 90   // head swings to the right, poking inward
        case .right: return -90 // head swings to the left, poking inward
        }
    }

    /// The top edge hangs the character upside down so its head points
    /// down into the screen.
    static func isVerticallyFlipped(for edge: PeekEdge) -> Bool { edge == .top }

    /// Equivalent transform in Core Graphics' y-up space, mapping the
    /// natural art into the oriented bounding box. Used to bake the
    /// hit-test mask; on-screen rendering uses the SwiftUI modifiers
    /// above so it stays resolution-independent per display.
    static func maskTransform(natural: CGSize, edge: PeekEdge) -> CGAffineTransform {
        let bounds = boundingSize(natural: natural, edge: edge)
        switch edge {
        case .bottom:
            return .identity
        case .top:
            return CGAffineTransform(translationX: 0, y: natural.height)
                .scaledBy(x: 1, y: -1)
        case .left, .right:
            // CG rotation is counterclockwise-positive, mirroring the
            // SwiftUI values above.
            let radians: CGFloat = (edge == .left) ? -.pi / 2 : .pi / 2
            return CGAffineTransform(translationX: bounds.width / 2, y: bounds.height / 2)
                .rotated(by: radians)
                .translatedBy(x: -natural.width / 2, y: -natural.height / 2)
        }
    }
}

// MARK: - Alpha mask

/// A coarse opacity map of an oriented sprite, so a click lands on the
/// character only where it is actually drawn.
struct AlphaMask {
    let width: Int
    let height: Int
    /// Row-major, row 0 = top (already flipped out of Core Graphics'
    /// bottom-up order so sampling matches the view's coordinates).
    private let alpha: [UInt8]

    init(width: Int, height: Int, alpha: [UInt8]) {
        self.width = width
        self.height = height
        self.alpha = alpha
    }

    /// `point` is in the mask's own space, top-left origin.
    func isOpaque(at point: CGPoint, threshold: UInt8 = 40) -> Bool {
        let x = Int(point.x.rounded(.down))
        let y = Int(point.y.rounded(.down))
        guard x >= 0, y >= 0, x < width, y < height else { return false }
        return alpha[y * width + x] >= threshold
    }
}

// MARK: - Layout

/// Everything needed to place one peek on screen. Rects inside the
/// window use a top-left origin to match SwiftUI.
struct PeekLayout {
    /// Window rect in global screen coordinates (AppKit, y-up).
    let windowFrame: CGRect
    /// Natural (unrotated) art size.
    let naturalSpriteSize: CGSize
    /// Oriented bounding size of the art.
    let fullSpriteSize: CGSize
    let anchoredEdge: PeekEdge

    /// The window is sized for the *deepest* lean, so this is its bounds.
    var spriteClipRect: CGRect {
        CGRect(origin: .zero, size: windowFrame.size)
    }

    /// How far the character pokes out along the reveal axis, as a
    /// fraction of its length. The window is built for `maxReveal`, so
    /// the character sits offset back from the edge at rest and only uses
    /// the full window while leaning out.
    private var revealAxisLength: CGFloat {
        switch anchoredEdge {
        case .top, .bottom: return fullSpriteSize.height
        case .left, .right: return fullSpriteSize.width
        }
    }

    /// Offset that puts the character at a given reveal fraction.
    /// `reveal == 0` tucks it fully out of sight; `reveal == maxReveal`
    /// fills the window.
    func offset(forReveal reveal: CGFloat) -> CGSize {
        let back = (PeekLayoutBuilder.maxRevealFraction - reveal) * revealAxisLength
        switch anchoredEdge {
        case .bottom: return CGSize(width: 0, height: back)
        case .top: return CGSize(width: 0, height: -back)
        case .left: return CGSize(width: -back, height: 0)
        case .right: return CGSize(width: back, height: 0)
        }
    }

    /// Top-left corner of the full (unclipped) sprite within the window
    /// at a given reveal, following the side its head is anchored to.
    func spriteOrigin(forReveal reveal: CGFloat) -> CGPoint {
        let clip = spriteClipRect
        let base: CGPoint
        switch anchoredEdge {
        case .bottom:
            base = CGPoint(x: clip.minX, y: clip.minY)
        case .top:
            base = CGPoint(x: clip.minX, y: clip.maxY - fullSpriteSize.height)
        case .left:
            base = CGPoint(x: clip.maxX - fullSpriteSize.width, y: clip.minY)
        case .right:
            base = CGPoint(x: clip.minX, y: clip.minY)
        }
        let shift = offset(forReveal: reveal)
        return CGPoint(x: base.x + shift.width, y: base.y + shift.height)
    }

    /// Whether a window-local point (top-left origin) lands on an opaque
    /// pixel of the *visible* part of the character. Everything else has
    /// to fall through to whatever app is underneath.
    func hitsSprite(at point: CGPoint, mask: AlphaMask, reveal: CGFloat) -> Bool {
        guard spriteClipRect.contains(point) else { return false }
        let origin = spriteOrigin(forReveal: reveal)
        return mask.isOpaque(at: CGPoint(x: point.x - origin.x, y: point.y - origin.y))
    }
}

enum PeekLayoutBuilder {
    /// How much of the character shows while it's just sitting there.
    ///
    /// The characters grin the whole time and the tongue hangs to about
    /// 0.65 of the art, while the arms start around 0.685 — so this sits
    /// between the two: the whole smile is in frame, and a paw wave is
    /// still a surprise. Scripts/gen_gestures.py prints both bounds.
    static let restRevealFraction: CGFloat = 0.667
    /// How far it leans out to wave a paw. The arms sit about three
    /// quarters of the way down the art, below the resting cut, so a paw
    /// wave is invisible unless the character leans further out for it.
    /// The window is built to this depth, so it is also the ceiling for
    /// any gesture's `requiredReveal`.
    static let maxRevealFraction: CGFloat = 0.8
    /// Keeps a peek from butting right up against a corner.
    static let edgeMargin: CGFloat = 40

    /// Builds a layout for one peek.
    ///
    /// `visibleFrame` (not `frame`) is deliberate: it excludes the menu
    /// bar and Dock, which sit at higher window levels than this overlay
    /// and would otherwise cover a character peeking from that side.
    static func make(
        edge: PeekEdge,
        visibleFrame: CGRect,
        naturalSize: CGSize,
        randomSource: (ClosedRange<CGFloat>) -> CGFloat = { CGFloat.random(in: $0) }
    ) -> PeekLayout {
        let full = PeekOrientation.boundingSize(natural: naturalSize, edge: edge)

        // The window is sized for the deepest lean and always sits wholly
        // on screen; the character slides within it. Nothing depends on
        // a window hanging off the edge, which would misbehave when
        // another display is arranged on that side.
        let windowSize: CGSize
        switch edge {
        case .top, .bottom:
            windowSize = CGSize(width: full.width, height: full.height * maxRevealFraction)
        case .left, .right:
            windowSize = CGSize(width: full.width * maxRevealFraction, height: full.height)
        }

        // Slide position along the edge, clamped so the window always
        // stays fully inside the visible area even on a small display.
        let origin: CGPoint
        switch edge {
        case .top, .bottom:
            let low = visibleFrame.minX + edgeMargin
            let high = visibleFrame.maxX - windowSize.width - edgeMargin
            let x = high > low
                ? randomSource(low...high)
                : max(visibleFrame.minX, visibleFrame.minX + (visibleFrame.width - windowSize.width) / 2)
            let y = (edge == .bottom)
                ? visibleFrame.minY
                : visibleFrame.maxY - windowSize.height
            origin = CGPoint(x: x, y: y)
        case .left, .right:
            let low = visibleFrame.minY + edgeMargin
            let high = visibleFrame.maxY - windowSize.height - edgeMargin
            let y = high > low
                ? randomSource(low...high)
                : max(visibleFrame.minY, visibleFrame.minY + (visibleFrame.height - windowSize.height) / 2)
            let x = (edge == .left)
                ? visibleFrame.minX
                : visibleFrame.maxX - windowSize.width
            origin = CGPoint(x: x, y: y)
        }

        return PeekLayout(
            windowFrame: CGRect(origin: origin, size: windowSize),
            naturalSpriteSize: naturalSize,
            fullSpriteSize: full,
            anchoredEdge: edge
        )
    }
}

extension CGSize {
    /// The dimension along a given edge's reveal axis.
    func widthOrHeight(_ edge: PeekEdge) -> CGFloat {
        switch edge {
        case .top, .bottom: return height
        case .left, .right: return width
        }
    }
}
