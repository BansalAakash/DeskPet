import Foundation

/// One peekable character. `id` matches the resource subfolder name
/// under Resources/species/.
struct Species: Identifiable, Hashable {
    let id: String
    let displayName: String
    let greetings: [String]

    var randomGreeting: String { greetings.randomElement() ?? "Hi!" }

    static let all: [Species] = [
        Species(id: "cat", displayName: "Cat", greetings: ["Hi!", "Meow!", "Hello!", "Purr…"]),
        Species(id: "dog", displayName: "Dog", greetings: ["Hi!", "Woof!", "Hello!", "Boop!"])
    ]

    static let byID: [String: Species] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
}

enum PeekEdge: CaseIterable {
    case top
    case bottom
    case left
    case right
}
