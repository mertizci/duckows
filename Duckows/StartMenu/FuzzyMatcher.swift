import Foundation

/// Ranks apps for the Start menu's search field.
///
/// Pure and synchronous: a couple of hundred apps score in well under a
/// millisecond, so there is nothing to debounce.
enum FuzzyMatcher {
    /// Higher is better; nil means no match at all.
    static func score(_ candidate: String, query: String) -> Int? {
        guard !query.isEmpty else { return 0 }

        let name = candidate.lowercased()
        let needle = query.lowercased()

        if name == needle { return 10_000 }

        // Shorter prefix matches win: typing "mail" should not rank
        // "Mailbutler" above "Mail".
        if name.hasPrefix(needle) { return 5_000 + max(0, 200 - name.count) }

        if let acronym = acronymScore(candidate, needle: needle) { return acronym }

        if let range = name.range(of: needle) {
            let offset = name.distance(from: name.startIndex, to: range.lowerBound)
            return 2_000 - min(offset, 500)
        }

        return subsequenceScore(name, needle: needle)
    }

    /// "ss" matching "System Settings".
    private static func acronymScore(_ candidate: String, needle: String) -> Int? {
        let initials = candidate
            .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
            .compactMap { $0.first?.lowercased() }
            .joined()
        guard !initials.isEmpty else { return nil }
        if initials == needle { return 4_000 }
        if initials.hasPrefix(needle) { return 3_000 }
        return nil
    }

    /// Every character present in order, with gaps penalised and hits on word
    /// boundaries rewarded.
    private static func subsequenceScore(_ name: String, needle: String) -> Int? {
        var score = 1_000
        var index = name.startIndex
        var lastMatch: String.Index?

        for character in needle {
            guard let found = name[index...].firstIndex(of: character) else { return nil }
            if let last = lastMatch {
                let gap = name.distance(from: last, to: found) - 1
                score -= min(gap * 8, 120)
            }
            let isBoundary = found == name.startIndex
                || name[name.index(before: found)] == " "
                || name[name.index(before: found)] == "-"
            if isBoundary { score += 25 }

            lastMatch = found
            index = name.index(after: found)
        }
        return max(score, 1)
    }
}
