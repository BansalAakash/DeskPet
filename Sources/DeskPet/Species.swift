import Foundation

/// One peekable character. `id` matches the resource subfolder name
/// under Resources/species/.
struct Species: Identifiable, Hashable {
    let id: String
    let displayName: String

    static let all: [Species] = [
        Species(id: "cat", displayName: "Cat"),
        Species(id: "dog", displayName: "Dog")
    ]
}

enum PeekEdge: CaseIterable {
    case top
    case bottom
    case left
    case right
}
