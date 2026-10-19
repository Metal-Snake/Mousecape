import Foundation

/// Keys of a property list this version doesn't know, kept as they were, so saving a cape
/// doesn't lose what a later version or another tool put there. Stored as a binary property
/// list to stay `Sendable` and `Equatable`.
public struct OtherKeys: Equatable, Sendable {
    private let data: Data?

    public static let none = OtherKeys([:])

    /// The entries of `dictionary` whose keys aren't in `known`.
    init(_ dictionary: [String: Any], known: Set<String> = []) {
        let other = dictionary.filter { !known.contains($0.key) }
        data = other.isEmpty ? nil
            : try? PropertyListSerialization.data(fromPropertyList: other, format: .binary, options: 0)
    }

    var dictionary: [String: Any] {
        guard let data,
              let dictionary = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return dictionary
    }

    var isEmpty: Bool { data == nil }

    /// `known` entries on top of the kept ones.
    func merged(with known: [String: Any]) -> [String: Any] {
        dictionary.merging(known) { _, new in new }
    }
}
