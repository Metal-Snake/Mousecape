import Foundation

/// Several versions of one theme installed side by side, such as Bibata's Regular, Large and
/// Extra-Large: each needs its own identifier and a name that says which version it is.
/// Converted themes get their identifier from their name, so versions with the same name
/// would otherwise replace each other.
public enum ThemeVersions {
    /// One version: the converted cape, its folder in the archive and what kind of theme it
    /// is ("Linux", "Windows").
    public struct Version: Sendable {
        public var cape: Cape
        public var variant: String?
        public var kind: String

        public init(cape: Cape, variant: String?, kind: String) {
            self.cape = cape
            self.variant = variant
            self.kind = kind
        }
    }

    /// A short label for each version: the words of its folder name that the other
    /// versions' folders don't share ("Large Windows" from `Bibata-Modern-Classic-Large-Windows`
    /// next to `Bibata-Modern-Classic`), plus its kind when the kinds differ. A version
    /// whose label would still match another's gets a number.
    public static func labels(for versions: [Version]) -> [String] {
        let words = versions.map { version in
            version.variant.map { variant in
                (variant as NSString).lastPathComponent
                    .split { !$0.isLetter && !$0.isNumber }
                    .map(String.init)
            } ?? []
        }
        // The words all folder names start and end with: the theme's own name, mostly. Only
        // whole runs at the ends count, so "Large" stays in both "Large" and "Extra Large".
        let named = words.filter { !$0.isEmpty }.map { $0.map { $0.lowercased() } }
        func commonRun(_ lists: [[String]]) -> Int {
            guard let shortest = lists.map(\.count).min() else { return 0 }
            return (0..<shortest).first { position in Set(lists.map { $0[position] }).count > 1 } ?? shortest
        }
        let prefix = named.count > 1 ? commonRun(named) : 0
        // An end run may not take a label's last word, which would leave it empty.
        let rest = named.map { Array($0.dropFirst(prefix)) }
        let suffix = named.count > 1 ? min(commonRun(rest.map { $0.reversed() }), max((rest.map(\.count).min() ?? 0) - 1, 0)) : 0
        let kindsDiffer = Set(versions.map(\.kind)).count > 1
        var labels = versions.indices.map { index -> String in
            let own = words[index]
            var label = own.isEmpty ? [] : Array(own.dropFirst(prefix).dropLast(suffix))
            if kindsDiffer && !label.contains(where: { $0.caseInsensitiveCompare(versions[index].kind) == .orderedSame }) {
                label.append(versions[index].kind)
            }
            return label.isEmpty ? versions[index].kind : label.joined(separator: " ")
        }
        // Still the same: number them in order.
        for index in labels.indices {
            let label = labels[index]
            let same = labels.indices.filter { labels[$0] == label }
            guard same.count > 1 else { continue }
            for (number, other) in same.enumerated() {
                labels[other] = "\(label) \(number + 1)"
            }
        }
        return labels
    }

    /// The capes to install, told apart: a cape whose name or identifier another version
    /// shares gets its label in its name ("Bibata Modern Classic (Large Windows)") and in
    /// its identifier (`local.windows.bibatamodernclassic.largewindows`). Others stay as
    /// they are, as does a single version.
    public static func distinguished(_ versions: [Version]) -> [Cape] {
        guard versions.count > 1 else { return versions.map(\.cape) }
        let labels = labels(for: versions)
        func shared<Value: Hashable>(_ value: (Cape) -> Value) -> Set<Value> {
            let all = versions.map { value($0.cape) }
            return Set(all.filter { item in all.filter { $0 == item }.count > 1 })
        }
        let sharedNames = shared(\.name)
        let sharedIdentifiers = shared(\.identifier)
        return versions.indices.map { index in
            var cape = versions[index].cape
            guard sharedNames.contains(cape.name) || sharedIdentifiers.contains(cape.identifier) else { return cape }
            cape.name += " (\(labels[index]))"
            cape.identifier += "." + Cape.slug(labels[index], otherwise: "\(index + 1)")
            return cape
        }
    }
}
