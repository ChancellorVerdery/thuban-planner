import Foundation

/// Decides which UNC Charlotte RMP profiles are the Banner instructor.
///
/// Rules (all comparisons on normalized names — case, diacritics and punctuation ignored):
/// - Family name: EXACT when the RMP last name equals the Banner family name, separators ignored ("Van Dyke" =
///   "VanDyke"; with "First Middle Last" any run of trailing words may be the family name). PARTIAL when one side is
///   a hyphenated / two-part name containing the other ("Mohiuddin-Jacobs" vs "Jacobs").
/// - Given name: EXACT; NICKNAME (one is a prefix of the other, ≥ 3 letters — "Chris"/"Christopher" — or a common
///   nickname pair — "Richard"/"Ritchie"); INITIAL (one side is a single letter).
/// - Strong = exact family + exact given. Good = exact family + nickname given, or partial family + exact given.
///   Weak = exact family + initial given.
/// - Strong matches are one person: they are combined (with any good match whose given name is compatible with
///   them all — "Chris" and "Christopher"), across both UNC Charlotte pages and duplicate profiles on one page.
/// - Otherwise good matches, then weak ones, are grouped into people (mutually compatible given names). One person →
///   found. Several → the ones whose RMP department fits the course subject; exactly one → found, else ambiguous.
public enum RMPMatcher {
    public enum GivenMatch: Int, Comparable, Sendable {
        case none = 0, initial, nickname, exact
        public static func < (a: GivenMatch, b: GivenMatch) -> Bool { a.rawValue < b.rawValue }
    }

    public enum FamilyMatch: Int, Comparable, Sendable {
        case none = 0, partial, exact
        public static func < (a: FamilyMatch, b: FamilyMatch) -> Bool { a.rawValue < b.rawValue }
    }

    public enum Strength: Int, Comparable, Sendable {
        case none = 0, weak, good, strong
        public static func < (a: Strength, b: Strength) -> Bool { a.rawValue < b.rawValue }
    }

    // MARK: Name pieces of an RMP profile

    /// The RMP given name, normalized ("Stuart " → "stuart", "John David" → "john").
    static func given(_ t: RMPTeacher) -> String {
        t.firstName.split(whereSeparator: { $0.isWhitespace }).first.map { RMPPersonName.normalizedWord(String($0)) } ?? ""
    }

    /// The RMP family name parts; a last name that repeats the first name ("Greg" "Greg Perkins") drops it.
    static func familyParts(_ t: RMPTeacher) -> [String] {
        var parts = RMPPersonName.parts(t.lastName)
        let first = RMPPersonName.parts(t.firstName)
        if !first.isEmpty, parts.count > first.count, Array(parts.prefix(first.count)) == first { parts.removeFirst(first.count) }
        return parts
    }

    // MARK: Comparisons

    public static func family(_ name: RMPPersonName, _ t: RMPTeacher) -> FamilyMatch {
        let rmp = familyParts(t)
        guard !rmp.isEmpty else { return .none }
        let joined = rmp.joined()
        if name.possibleLastParts.contains(where: { $0.joined() == joined }) { return .exact }
        let banner = Set(name.lastParts), other = Set(rmp)
        let shared = banner.intersection(other).filter { $0.count >= 2 }
        if !shared.isEmpty, banner.isSubset(of: other) || other.isSubset(of: banner) { return .partial }
        return .none
    }

    public static func givenMatch(_ a: String, _ b: String) -> GivenMatch {
        guard !a.isEmpty, !b.isEmpty else { return .none }
        if a == b { return .exact }
        if a.count == 1 || b.count == 1 { return a.first == b.first ? .initial : .none }
        if min(a.count, b.count) >= 3, a.hasPrefix(b) || b.hasPrefix(a) { return .nickname }
        if nicknameGroups.contains(where: { $0.contains(a) && $0.contains(b) }) { return .nickname }
        return .none
    }

    /// The Banner given name against an RMP profile; a first initial also tries the middle name ("J. David Smith").
    static func given(_ name: RMPPersonName, _ t: RMPTeacher) -> GivenMatch {
        let rmp = given(t)
        var best = givenMatch(name.first, rmp)
        if let middle = name.middle { best = max(best, givenMatch(middle, rmp) == .exact ? .nickname : givenMatch(middle, rmp)) }
        return best
    }

    public static func strength(_ name: RMPPersonName, _ t: RMPTeacher) -> Strength {
        switch (family(name, t), given(name, t)) {
        case (.exact, .exact): return .strong
        case (.exact, .nickname), (.partial, .exact): return .good
        case (.exact, .initial): return .weak
        default: return .none
        }
    }

    /// Worth keeping (and caching) as a candidate for this name.
    public static func isCandidate(_ name: RMPPersonName, _ t: RMPTeacher) -> Bool { strength(name, t) > .none }

    /// Two profiles can be the same person: compatible given names (exact or nickname) and family names.
    static func samePerson(_ a: RMPTeacher, _ b: RMPTeacher) -> Bool {
        guard givenMatch(given(a), given(b)) >= .nickname else { return false }
        let fa = Set(familyParts(a)), fb = Set(familyParts(b))
        return fa == fb || fa.isSubset(of: fb) || fb.isSubset(of: fa)
    }

    // MARK: Matching

    /// The conclusion for `name` teaching a course in `subject` ("PHYS"), from UNC Charlotte `candidates`.
    public static func match(name: RMPPersonName, candidates: [RMPTeacher], subject: String?) -> RMPMatch {
        var seen = Set<String>()
        let unique = candidates.filter { RateMyProfessors.school(legacyId: $0.schoolLegacyId) != nil && seen.insert($0.id).inserted }
        let graded = unique.map { (teacher: $0, strength: strength(name, $0)) }.filter { $0.strength > .none }
        let strong = graded.filter { $0.strength == .strong }.map(\.teacher)
        if !strong.isEmpty {
            let extras = graded.filter { $0.strength == .good }.map(\.teacher).filter { t in strong.allSatisfy { samePerson($0, t) } }
            return .found(RMPRating(profiles: strong + extras))
        }
        for level in [Strength.good, .weak] {
            let pool = graded.filter { $0.strength == level }.map(\.teacher)
            guard !pool.isEmpty else { continue }
            let people = cluster(pool)
            if people.count == 1 { return .found(RMPRating(profiles: people[0])) }
            if let subject {
                let fitting = people.filter { $0.contains { RMPDepartments.fits(department: $0.department, subject: subject) } }
                if fitting.count == 1 { return .found(RMPRating(profiles: fitting[0])) }
            }
            return .ambiguous(pool.sorted { $0.numRatings != $1.numRatings ? $0.numRatings > $1.numRatings : $0.legacyId < $1.legacyId })
        }
        return .notFound
    }

    /// Groups profiles into people: most-rated first, each joins the first group it is compatible with throughout.
    static func cluster(_ teachers: [RMPTeacher]) -> [[RMPTeacher]] {
        var groups: [[RMPTeacher]] = []
        for t in teachers.sorted(by: { $0.numRatings != $1.numRatings ? $0.numRatings > $1.numRatings : $0.legacyId < $1.legacyId }) {
            if let i = groups.firstIndex(where: { $0.allSatisfy { samePerson($0, t) } }) { groups[i].append(t) } else { groups.append([t]) }
        }
        return groups
    }

    /// Common English given-name nicknames that are not simple prefixes.
    static let nicknameGroups: [Set<String>] = [
        ["richard", "rick", "rich", "ricky", "ritchie", "richie", "dick"], ["william", "will", "bill", "billy", "liam"],
        ["robert", "rob", "bob", "bobby", "robbie", "bert"], ["james", "jim", "jimmy", "jamie"], ["john", "jack", "johnny"],
        ["joseph", "joe", "joey"], ["michael", "mike", "mikey", "mick"], ["thomas", "tom", "tommy"],
        ["charles", "charlie", "chuck"], ["christopher", "chris", "kit"], ["christine", "christina", "chris", "tina"],
        ["daniel", "dan", "danny"], ["david", "dave"], ["edward", "ed", "eddie", "ted", "ned"],
        ["elizabeth", "liz", "beth", "betsy", "eliza", "lizzie", "betty"],
        ["katherine", "catherine", "kathryn", "kate", "katie", "kathy", "cathy", "kat"],
        ["margaret", "maggie", "meg", "peggy"], ["patricia", "pat", "patty", "trish"], ["patrick", "pat"],
        ["jennifer", "jen", "jenny"], ["rebecca", "becky", "becca"], ["susan", "sue", "suzy"],
        ["deborah", "debra", "deb", "debbie"], ["anthony", "tony"], ["alexander", "alex", "sandy"],
        ["alexandra", "alex", "sandra"], ["benjamin", "ben", "benny"], ["nathan", "nathaniel", "nate"],
        ["gregory", "greg"], ["jeffrey", "geoffrey", "jeff"], ["kenneth", "ken", "kenny"], ["lawrence", "larry"],
        ["matthew", "matt"], ["nicholas", "nick"], ["samuel", "sam"], ["stephen", "steven", "steve"],
        ["timothy", "tim"], ["andrew", "andy", "drew"], ["douglas", "doug"], ["gerald", "jerry"], ["peter", "pete"],
        ["ronald", "ron"], ["donald", "don"], ["raymond", "ray"], ["zachary", "zach", "zack"],
        ["victoria", "vicky", "tori"], ["abigail", "abby"], ["pamela", "pam"], ["cynthia", "cindy"],
        ["frederick", "fred"], ["walter", "walt"], ["harold", "harry", "hal"], ["henry", "hank", "harry"],
        ["joshua", "josh"], ["jonathan", "jon"], ["phillip", "philip", "phil"], ["theodore", "ted", "teddy", "theo"],
        ["leonard", "leo", "len"], ["eugene", "gene"], ["albert", "al"], ["alan", "allan", "allen", "al"],
        ["jacqueline", "jackie"], ["judith", "judy"], ["kimberly", "kim"], ["melissa", "missy"], ["suzanne", "susan", "sue"],
    ]
}

/// UNC Charlotte subject codes → words that appear in RMP department names (for telling same-named professors
/// apart). Unknown subjects never filter.
public enum RMPDepartments {
    static let keywords: [String: [String]] = [
        "ACCT": ["accounting"], "AFRS": ["africana", "african"], "ANTH": ["anthropology"], "ARCH": ["architecture"],
        "ARTB": ["art"], "ARTE": ["art"], "ARTH": ["art"], "ARTL": ["art"], "ARTZ": ["art"], "ASTR": ["physics", "astronomy"],
        "BINF": ["bioinformatics", "biology"], "BIOL": ["biology", "biological"], "BLAW": ["business law", "business"],
        "BPHD": ["business"], "CEGR": ["civil", "engineering"], "CHEM": ["chemistry"], "CHIN": ["chinese", "languages"],
        "COMM": ["communication"], "CRJU": ["criminal justice", "criminology"], "CSLG": ["counseling"], "DANC": ["dance"],
        "ECGR": ["electrical", "computer engineering", "engineering"], "ECON": ["economics"], "EDUC": ["education"],
        "ENGL": ["english", "writing"], "ENGR": ["engineering"], "ENVS": ["environmental"], "ESCI": ["earth", "geology"],
        "ETCE": ["engineering technology", "engineering"], "ETEE": ["engineering technology", "engineering"],
        "ETME": ["engineering technology", "engineering"], "EXER": ["kinesiology", "exercise"], "FILM": ["film"],
        "FINN": ["finance"], "FREN": ["french", "languages"], "GEOG": ["geography"], "GERM": ["german", "languages"],
        "GRMN": ["german", "languages"], "HIST": ["history"], "HLTH": ["health"], "HONR": ["honors"],
        "INFO": ["information", "computer"], "ITCS": ["computer science", "computing", "information"],
        "ITIS": ["information", "computer science", "computing"], "ITSC": ["computer science", "computing", "information"],
        "JAPN": ["japanese", "languages"], "KNES": ["kinesiology"], "LBST": ["liberal studies"], "LTAM": ["latin american"],
        "MATH": ["mathematics", "math", "statistics"], "MBAD": ["business"], "MEGR": ["mechanical", "engineering"],
        "MGMT": ["management", "business"], "MKTG": ["marketing"], "MUSC": ["music"], "NURS": ["nursing"],
        "OPTI": ["optics", "optical", "physics"], "OPRS": ["operations", "business"], "PHIL": ["philosophy"],
        "PHYS": ["physics", "astronomy", "optics"], "POLS": ["political"], "PSYC": ["psychology"],
        "PUBH": ["public health", "health"], "RELS": ["religious", "religion"], "SEGR": ["systems engineering", "engineering"],
        "SOCY": ["sociology"], "SOWK": ["social work"], "SPAN": ["spanish", "languages"], "STAT": ["statistics", "mathematics"],
        "THEA": ["theatre", "theater"], "WGST": ["women", "gender"],
    ]

    /// True when the RMP department names the subject's field.
    public static func fits(department: String, subject: String) -> Bool {
        guard let words = keywords[subject.uppercased()] else { return false }
        let dept = " " + RMPPersonName.normalize(department).replacingOccurrences(of: "-", with: " ") + " "
        return words.contains { dept.contains(" \($0)") }
    }
}
