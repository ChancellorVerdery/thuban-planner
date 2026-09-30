import Foundation

/// An instructor name from Banner, parsed for matching against Rate My Professors.
///
/// Banner's `displayName` is usually "First Last" at UNC Charlotte ("Ritchie Dudley"), sometimes "Last, First
/// Middle". Words keep their original spelling for display and search; matching uses normalized "parts":
/// case-, diacritic- and punctuation-insensitive, hyphenated words split ("Mohiuddin-Jacobs" → mohiuddin, jacobs).
public struct RMPPersonName: Hashable, Sendable {
    /// Display words, first name first, suffixes (Jr., III, PhD) and titles (Dr.) removed.
    public var words: [String]
    /// How many leading `words` are the given name(s). With "First Middle Last" (no comma) only the first word is
    /// known to be a given name and only the last a family name; middle words may be either.
    public var givenCount: Int
    /// True for "Last, First" (the split between given and family names is known).
    public var commaForm: Bool

    /// "Ritchie Dudley".
    public var displayName: String { words.joined(separator: " ") }

    /// Cache key: normalized parts, space separated ("farida mohiuddin jacobs").
    public var key: String { words.flatMap(Self.parts).joined(separator: " ") }

    /// The given name used for matching (normalized, hyphens dropped): "ritchie".
    public var first: String { Self.normalizedWord(words[0]) }

    /// The middle word when the first is only an initial ("J. David Smith" → "david").
    public var middle: String? {
        guard words.count >= 3, first.count == 1 else { return nil }
        let m = Self.normalizedWord(words[1])
        return m.isEmpty ? nil : m
    }

    /// The family-name words known for certain ("Mohiuddin-Jacobs"; "Van Dyke" in comma form).
    public var lastWords: [String] { commaForm ? Array(words[givenCount...]) : [words[words.count - 1]] }

    /// Parts of the certain family name: ["mohiuddin", "jacobs"].
    public var lastParts: [String] { lastWords.flatMap(Self.parts) }

    /// Suffixes of the words that could be the whole family name (no comma: any run ending at the last word that
    /// leaves the first word as the given name; comma: exactly the family words), as normalized parts.
    public var possibleLastParts: [[String]] {
        if commaForm { return [lastParts] }
        return (1..<words.count).map { Array(words[$0...]).flatMap(Self.parts) }
    }

    /// What to type into RMP's search (it matches whole names, not substrings): the family name as written, plus
    /// each part of a hyphenated or multi-word family name, plus middle + last for a "First Middle Last" name.
    public var searchTexts: [String] {
        var texts: [String] = [lastWords.joined(separator: " ")]
        let rawParts = lastWords.flatMap { $0.split(whereSeparator: { $0 == "-" || $0 == " " }).map(String.init) }
        if rawParts.count > 1 { texts += rawParts }
        if !commaForm, words.count >= 3 { texts.append(words[1...].joined(separator: " ")) }
        var seen = Set<String>()
        return texts.filter { !$0.isEmpty && Self.parts($0).joined().count >= 2 && seen.insert($0.lowercased()).inserted }.prefix(4).map { $0 }
    }

    private static let suffixes: Set<String> = ["jr", "sr", "ii", "iii", "iv", "phd", "md", "edd", "dds", "esq"]
    private static let titles: Set<String> = ["dr", "prof", "professor", "mr", "mrs", "ms", "mx"]
    /// Banner placeholders for "nobody assigned".
    private static let placeholders: Set<String> = ["tba", "staff", "to be announced", "tbd", "instructor", "faculty"]

    /// Nil for an empty name or a placeholder ("TBA", "Staff").
    public static func parse(_ raw: String) -> RMPPersonName? {
        let collapsed = BannerText.collapse(raw)
        guard !collapsed.isEmpty, !placeholders.contains(normalize(collapsed)) else { return nil }
        func clean(_ text: Substring) -> [String] {
            text.split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { word in
                let n = normalize(word)
                return !n.isEmpty && !suffixes.contains(n)
            }
        }
        var commaForm = false
        var given: [String]
        var family: [String]
        let halves = collapsed.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        if halves.count == 2, !clean(halves[0]).isEmpty, !clean(halves[1]).isEmpty {
            family = clean(halves[0])
            given = clean(halves[1])
            commaForm = true
        } else {
            let words = clean(Substring(collapsed.replacingOccurrences(of: ",", with: " ")))
            given = Array(words.prefix(1))
            family = Array(words.dropFirst())
        }
        while let t = given.first, titles.contains(normalize(t)), given.count + family.count > 2 { given.removeFirst() }
        if given.isEmpty, family.count >= 2 { given = [family.removeFirst()] }
        guard !given.isEmpty, !family.isEmpty else { return nil }
        return RMPPersonName(words: given + family, givenCount: given.count, commaForm: commaForm)
    }

    /// Lower-case, diacritics folded, apostrophes / periods / other punctuation removed; hyphens and spaces kept.
    public static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        var out = ""
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) { out.unicodeScalars.append(scalar) }
            else if scalar == "-" || scalar == "‐" || scalar == "–" { out.append("-") }
            else if CharacterSet.whitespaces.contains(scalar) { out.append(" ") }
            // apostrophes, periods, commas … dropped ("O'Brien" → "obrien", "J." → "j")
        }
        return BannerText.collapse(out)
    }

    /// Normalized parts of a word or phrase, split on hyphens and spaces.
    public static func parts(_ text: String) -> [String] {
        normalize(text).split(whereSeparator: { $0 == "-" || $0 == " " }).map(String.init)
    }

    /// A word normalized with its parts joined ("Mary-Kate" → "marykate").
    public static func normalizedWord(_ word: String) -> String { parts(word).joined() }
}
