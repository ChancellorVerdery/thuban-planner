import Foundation

/// A requirement read from a degree document: one class.
public struct DegreeItem: Hashable, Sendable, Identifiable {
    public var code: String
    public var title: String
    public var credits: Double?
    /// AND of OR-groups, from the document's "Prerequisite(s):" line (empty when the document has none).
    public var prereqGroups: [[String]]
    /// Same term or earlier: "Corequisite(s):" + "Pre- or Corequisite(s):".
    public var coreqGroups: [[String]]
    public var notes: [String]
    /// The section heading it was listed under ("Major Courses (59 credit hours)").
    public var section: String?

    public var id: String { code }

    public init(code: String, title: String = "", credits: Double? = nil, prereqGroups: [[String]] = [], coreqGroups: [[String]] = [],
                notes: [String] = [], section: String? = nil) {
        self.code = CourseCode.normalize(code)
        self.title = title
        self.credits = credits
        self.prereqGroups = prereqGroups
        self.coreqGroups = coreqGroups
        self.notes = notes
        self.section = section
    }
}

/// "Select four of the following" — a requirement the user satisfies by choosing.
public struct DegreeChoiceGroup: Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String
    /// Classes to choose (credits-based groups are converted at 3 credits a class, rounded up).
    public var pick: Int
    public var options: [DegreeItem]
    public var notes: [String]

    public init(id: String, label: String, pick: Int, options: [DegreeItem], notes: [String] = []) {
        self.id = id
        self.label = label
        self.pick = pick
        self.options = options
        self.notes = notes
    }
}

/// What a degree document says is required.
public struct ParsedDegreeDocument: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        /// A UNC Charlotte catalog (acalog) program page.
        case catalog
        /// A DegreeWorks audit: only "Still needed" requirements are read.
        case degreeWorks
        /// A checksheet / flowchart / any list of courses.
        case checksheet
    }

    public var kind: Kind
    /// "Mechanical Engineering, B.S.M.E.", "Minor in Mathematics" — nil when none was found.
    public var programName: String?
    public var required: [DegreeItem]
    public var choices: [DegreeChoiceGroup]
    /// Lines that mention a course but were not read as a requirement (prose, notes) — shown as warnings.
    public var skippedLines: [String]
}

/// Reads requirement lists from document text. Line based, format aware:
///
/// - **DegreeWorks** (text has "Still needed:"): each "Still needed:" block — "1 Class in MEGR 3114" is a required
///   class (titled by the requirement's label line above); "1 Class in MEGR 3216 / or 3221" or "4 Classes in MEGR 3090
///   or 3092 …" is a choice group; "additionally you need …" becomes a note. Completed classes are not requirements.
/// - **Catalog / checksheet**: a line that STARTS with a course code (after a bullet or "or") is a class: "MATH 2171 -
///   Differential Equations (3)", "ENGR 1300 Exploring Engineering (2)", "PHYS 2101 (3)", "MATH 2171  Differential
///   Equations  3". A line starting with "or" joins the previous class into a choose-one group. "Select / Choose N of
///   the following", "N of the following", "Two MATH courses: MATH 1103 or MATH 1241 or MATH 1242" open choice groups
///   that run to the next heading. "Prerequisite(s):", "Corequisite(s):", "Pre- or Corequisite(s):" and "Credit
///   Hours:" lines attach to the class above. Headings (no code; "… (12 credit hours)", "…:", a short title line)
///   close a choice group. Codes inside prose are skipped (listed as warnings).
public enum DegreeDocumentParser {
    public static func parse(_ text: String, heading: String? = nil) -> ParsedDegreeDocument {
        let raw = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let lines = joinBrokenCourseLines(raw).map(clean).filter { !$0.isEmpty }
        let isDegreeWorks = lines.contains { $0.hasPrefix("Still needed") } &&
            (text.contains("DegreeWorks") || text.contains("Degree progress") || text.contains("Audit date") || text.contains("Classes in") || text.contains("Class in"))
        var doc = isDegreeWorks ? parseDegreeWorks(lines) : parseList(lines)
        doc.programName = programName(lines: lines, heading: heading, kind: doc.kind)
        if !isDegreeWorks, text.contains("Credit Hours") || text.lowercased().contains("catalog") || heading != nil {
            doc.kind = .catalog
        }
        return doc
    }

    /// PDF text often breaks "PHYS 2101 - Physics for Science and Engineering I (3)" into "PHYS 2101", "-",
    /// "Physics for Science and Engineering I (3)". A line that is only a code, then exactly one dash line, then a
    /// code-free line ending in credits, is joined back (raw lines, before `clean` drops the dash).
    static func joinBrokenCourseLines(_ lines: [String]) -> [String] {
        var out: [String] = []
        var i = 0
        while i < lines.count {
            let line = lines[i].replacingOccurrences(of: #"^[•◦▪●]\s*"#, with: "", options: .regularExpression)
            if i + 2 < lines.count,
               line.range(of: #"^(or\s+)?[A-Z]{2,4}\s?\d{4}[A-Z]?\*?$"#, options: .regularExpression) != nil,
               ["-", "–", "—"].contains(lines[i + 1]),
               codes(in: lines[i + 2]).isEmpty, labelled(lines[i + 2]) == nil,
               lines[i + 2].range(of: #"\(\d+(\.\d+)?(\s*-\s*\d+)?\)\**$"#, options: .regularExpression) != nil {
                out.append("\(line) - \(lines[i + 2])")
                i += 3
                continue
            }
            out.append(line)
            i += 1
        }
        return out
    }

    static func clean(_ line: String) -> String {
        var s = line.replacingOccurrences(of: "\u{00a0}", with: " ").replacingOccurrences(of: "\t", with: " ")
        s = s.trimmingCharacters(in: .whitespaces)
        while let first = s.first, "•◦▪●○‣∙·*-–—".contains(first) {
            s.removeFirst()
            s = s.trimmingCharacters(in: .whitespaces)
        }
        return BannerText.collapse(s)
    }

    // MARK: Program name

    static func programName(lines: [String], heading: String?, kind: ParsedDegreeDocument.Kind) -> String? {
        let patterns = [
            #"^(Minor|Major|Concentration|Certificate) in [A-Z][A-Za-z&,' -]+$"#,
            #"^Bachelor of [A-Z][A-Za-z ]+ in [A-Z][A-Za-z&,' -]+$"#,
            #"^[A-Z][A-Za-z&' -]+, (B\.[A-Z]\.[A-Z.]*|B\.[A-Z]{1,4}\.?|Minor|Certificate|Undergraduate Certificate)$"#,
            #"^[A-Z][A-Za-z&' -]+ Minor$"#,
        ]
        if let heading, let match = firstMatch(in: [BannerText.collapse(heading)], patterns: patterns) { return match }
        // DegreeWorks: prefer a minor block when the audit is a minor's, else the major / degree.
        if let match = firstMatch(in: lines, patterns: patterns) {
            return match
        }
        return nil
    }

    private static func firstMatch(in lines: [String], patterns: [String]) -> String? {
        for line in lines.prefix(4000) {
            let candidate = line.replacingOccurrences(of: #"\s+(INCOMPLETE|COMPLETE|IN-PROGRESS)$"#, with: "", options: .regularExpression)
            guard candidate.count <= 90 else { continue }
            for pattern in patterns where candidate.range(of: pattern, options: .regularExpression) != nil {
                return candidate
            }
        }
        return nil
    }

    // MARK: Course lines

    static let numberWords: [String: Int] = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
                                            "nine": 9, "ten": 10, "a": 1, "an": 1]

    static func number(_ word: String) -> Int? { Int(word) ?? numberWords[word.lowercased()] }

    private static let courseLine = try! NSRegularExpression(pattern:
        #"^(?:(or|and)\s+)?([A-Z]{2,4})\s?(\d{4}[A-Z]?)\*?(?:\s*[-–—:]\s*|\s+|$)(.*)$"#)
    private static let creditsTail = try! NSRegularExpression(pattern:
        #"\s*\((\d+(?:\.\d+)?)(?:\s*[-–]\s*\d+(?:\.\d+)?)?\s*(?:credits?|credit hours|hours|cr\.?|each)?\)\s*(.*)$|\s+(\d+(?:\.\d+)?)\s*(?:credits?|cr\.?|credit hours|hours)?\s*$"#,
        options: [.caseInsensitive])

    /// A line that is one class: ("or"?, code, title, credits, trailing note).
    static func courseLine(_ line: String) -> (joiner: String?, code: String, title: String, credits: Double?, tail: String)? {
        let ns = line as NSString
        guard let m = courseLine.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func g(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
        let code = "\(g(2)!) \(g(3)!)"
        var rest = g(4) ?? ""
        // "MATH 1103* or MATH 1241* or …" is not one class.
        if rest.range(of: #"^or\s+[A-Z]{2,4}\s?\d{4}"#, options: .regularExpression) != nil { return nil }
        var credits: Double?
        var tail = ""
        let rns = rest as NSString
        if let c = creditsTail.firstMatch(in: rest, range: NSRange(location: 0, length: rns.length)) {
            let value = c.range(at: 1).location != NSNotFound ? rns.substring(with: c.range(at: 1)) : (c.range(at: 3).location != NSNotFound ? rns.substring(with: c.range(at: 3)) : nil)
            credits = value.flatMap(Double.init)
            if c.range(at: 2).location != NSNotFound { tail = rns.substring(with: c.range(at: 2)) }
            rest = rns.substring(to: c.range.location)
        }
        var title = rest.trimmingCharacters(in: CharacterSet(charactersIn: " -–—:"))
        // A title that is really prose ("ENGR 1300, ENGR 1301 …", "with a grade of C") is not a class line.
        if title.range(of: #"^(,|and\b|or\b|with\b|is\b|are\b|must\b|requires?\b)"#, options: [.regularExpression, .caseInsensitive]) != nil { return nil }
        if title.range(of: #"[A-Z]{2,4}\s?\d{4}"#, options: .regularExpression) != nil, title.count > 60 { return nil }
        title = title.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return (g(1)?.lowercased(), code, title, credits, tail.trimmingCharacters(in: CharacterSet(charactersIn: " ()")))
    }

    static func codes(in text: String) -> [String] {
        CatalogRequirementParser.tokens(text).compactMap { if case .code(let c) = $0 { return c }; return nil }
    }

    // MARK: Generic list (catalog page, checksheet)

    static func parseList(_ lines: [String]) -> ParsedDegreeDocument {
        var required: [DegreeItem] = []
        var choices: [DegreeChoiceGroup] = []
        var skipped: [String] = []
        var section: String?
        var openChoice: DegreeChoiceGroup?
        var last: (inChoice: Bool, index: Int)?
        var seen = Set<String>()

        func closeChoice() {
            if var group = openChoice, !group.options.isEmpty {
                // An "Option N" block: take all of its classes (or another option's).
                if group.pick == 0 { group.pick = group.options.count; group.notes.insert("Take every class of one option.", at: 0) }
                choices.append(group)
            }
            openChoice = nil
        }
        func newChoice(label: String, pick: Int) {
            closeChoice()
            openChoice = DegreeChoiceGroup(id: "choice-\(choices.count + 1)", label: label, pick: max(0, pick), options: [])
        }
        func attach(_ update: (inout DegreeItem) -> Void) {
            guard let last else { return }
            if last.inChoice {
                if openChoice != nil, openChoice!.options.indices.contains(last.index) { update(&openChoice!.options[last.index]) }
            } else if required.indices.contains(last.index) {
                update(&required[last.index])
            }
        }

        for line in lines {
            let lower = line.lowercased()
            // Requirement lines for the class above.
            if let (label, value) = labelled(line) {
                switch label {
                case "credits":
                    let v = value.range(of: #"\d+(\.\d+)?"#, options: .regularExpression).map { Double(value[$0]) } ?? nil
                    attach { if $0.credits == nil { $0.credits = v } }
                case "prereq":
                    let r = CatalogRequirementParser.parse(value)
                    attach { $0.prereqGroups += r.groups; $0.notes += r.notes }
                case "coreq", "precoreq":
                    let r = CatalogRequirementParser.parse(value)
                    attach { $0.coreqGroups += r.groups; $0.notes += r.notes }
                default:
                    attach { $0.notes.append(value) }
                }
                continue
            }
            // "Select four of the following." / "Choose 2 courses from:" / "One of the following:"
            if let pick = selectCount(lower) {
                newChoice(label: [section, line].compactMap { $0 }.joined(separator: " — "), pick: pick)
                last = nil
                continue
            }
            // "MATH 3XXX-4XXX Mathematics Elective (3)", "PHYS XXXX - Physics Elective Course (3)*": a wildcard.
            if line.range(of: #"^[A-Z]{2,4}\s?[0-9]?X{2,4}"#, options: .regularExpression) != nil {
                let note = line.replacingOccurrences(of: #"\s*\(\d+\)\**\s*$"#, with: "", options: .regularExpression)
                if openChoice != nil { openChoice!.notes.append("Or: " + note) } else { skipped.append(line) }
                continue
            }
            // "Two MATH courses: MATH 1103* or MATH 1241* or MATH 1242* (3 each)" (codes right away, or after a short
            // label ending in ":"; never codes inside a sentence).
            let inline = codes(in: line)
            if inline.count >= 2, line.range(of: #"\bor\b"#, options: .regularExpression) != nil, inlineChoicePrefixOK(line),
               courseLine(line) == nil || line.range(of: #"^[A-Z]{2,4}\s?\d{4}\*?\s+or\b"#, options: .regularExpression) != nil,
               !lower.contains("prerequisite"), !lower.contains("grade") {
                let firstWord = line.split(separator: " ").first.map(String.init) ?? ""
                let pick = number(firstWord.trimmingCharacters(in: CharacterSet(charactersIn: ":"))) ?? 1
                let credits = line.range(of: #"\((\d+)\s*(each|credits?)?\)"#, options: .regularExpression)
                    .flatMap { Double(line[$0].filter(\.isNumber)) }
                closeChoice()
                let label = line.replacingOccurrences(of: #":.*$"#, with: "", options: .regularExpression)
                var local = Set<String>()
                let options = inline.filter { local.insert($0).inserted }.map { DegreeItem(code: $0, credits: credits, section: section) }
                if !options.isEmpty {
                    choices.append(DegreeChoiceGroup(id: "choice-\(choices.count + 1)", label: label, pick: pick, options: options))
                }
                last = nil
                continue
            }
            if let course = courseLine(line) {
                let code = CourseCode.normalize(course.code)
                var item = DegreeItem(code: code, title: course.title, credits: course.credits, section: section)
                if !course.tail.isEmpty { item.notes.append(course.tail) }
                if course.joiner == "or" {
                    // Join with the class above into a choose-one group.
                    if var group = openChoice {
                        if !group.options.contains(where: { $0.code == code }) { group.options.append(item) }
                        openChoice = group
                        last = (true, group.options.count - 1)
                    } else if let previous = last, !previous.inChoice, required.indices.contains(previous.index) {
                        let first = required.remove(at: previous.index)
                        seen.remove(first.code)
                        let label = [section, "\(first.code) or \(code)"].compactMap { $0 }.joined(separator: " — ")
                        choices.append(DegreeChoiceGroup(id: "choice-\(choices.count + 1)", label: label, pick: 1, options: [first, item]))
                        last = nil
                    } else if let lastChoice = choices.indices.last, last == nil {
                        if !choices[lastChoice].options.contains(where: { $0.code == code }) { choices[lastChoice].options.append(item) }
                    }
                    continue
                }
                if openChoice != nil {
                    if !openChoice!.options.contains(where: { $0.code == code }) { openChoice!.options.append(item) }
                    last = (true, openChoice!.options.count - 1)
                } else {
                    guard seen.insert(code).inserted else { continue }
                    required.append(item)
                    last = (false, required.count - 1)
                }
                continue
            }
            if !inline.isEmpty {
                skipped.append(line)
                continue
            }
            // "Restricted Elective Course (3 credit hours)", "Design Elective: …", "*Elective Courses", "Option 2":
            // the classes listed under it are choices, not requirements.
            if let pick = electiveHeading(line) {
                section = line
                newChoice(label: line, pick: pick)
                last = nil
                continue
            }
            if isHeading(line) {
                // A strong heading ("… (12 credit hours)", "…:", "Total …") always ends a choice list; a weak one (a
                // short title-case line — in PDFs often stray navigation text) only ends one that has classes.
                if isStrongHeading(line) || !(openChoice?.options.isEmpty ?? true) { closeChoice() }
                section = line
                last = nil
            }
        }
        closeChoice()
        return ParsedDegreeDocument(kind: .checksheet, programName: nil, required: required, choices: choices, skippedLines: skipped)
    }

    static func labelled(_ line: String) -> (String, String)? {
        let table: [(String, String)] = [
            ("Pre- or Corequisite(s):", "precoreq"), ("Pre- or Corequisites:", "precoreq"), ("Pre- or Corequisite:", "precoreq"),
            ("Prerequisite(s):", "prereq"), ("Prerequisites:", "prereq"), ("Prerequisite:", "prereq"), ("Prereq:", "prereq"), ("Prereqs:", "prereq"),
            ("Corequisite(s):", "coreq"), ("Corequisites:", "coreq"), ("Corequisite:", "coreq"), ("Coreq:", "coreq"), ("Coreqs:", "coreq"),
            ("Credit Hours:", "credits"), ("Credits:", "credits"),
            ("Restriction(s):", "note"), ("Restrictions:", "note"),
        ]
        for (prefix, key) in table where line.lowercased().hasPrefix(prefix.lowercased()) {
            return (key, String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    static func selectCount(_ lower: String) -> Int? {
        // "Select four of the following." / "Choose 2:" — but not a sentence like "Complete at least 12 credits of
        // courses at Charlotte, including …".
        guard lower.count <= 140 else { return nil }
        let instruction = lower.hasPrefix("select") || lower.hasPrefix("choose") || lower.contains("following") || lower.hasSuffix(":")
        guard instruction, !lower.contains("including") else { return nil }
        let patterns = [
            #"^(?:select|choose|complete|take)\s+(?:at least\s+|any\s+)?(\w+)\s+(?:of the following|courses?|classes|from|electives?|credit hours|credits|hours)"#,
            #"^(\w+)\s+(?:course|courses|class|classes)?\s*(?:of|from) the following"#,
        ]
        for pattern in patterns {
            guard let range = lower.range(of: pattern, options: .regularExpression) else { continue }
            let match = String(lower[range])
            let words = match.split(separator: " ").map(String.init)
            for word in words { if let n = number(word) {
                // "Select 6 credit hours" → classes at 3 credits each.
                if match.contains("credit") || match.contains("hours") { return max(1, Int((Double(n) / 3).rounded(.up))) }
                return n
            } }
        }
        return nil
    }

    /// Text before the first code is empty, or a short label ending in ":" ("Two MATH courses:").
    static func inlineChoicePrefixOK(_ line: String) -> Bool {
        guard let range = line.range(of: #"[A-Z]{2,4}\s?\d{4}"#, options: .regularExpression) else { return false }
        let prefix = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
        guard prefix.isEmpty || (prefix.hasSuffix(":") && prefix.count <= 40) else { return false }
        // After the label: only codes, "or" / "and", punctuation and a credits note — not a sentence.
        var rest = String(line[range.lowerBound...])
        rest = rest.replacingOccurrences(of: #"[A-Z]{2,4}\s?\d{4}[A-Z]?\*?"#, with: " ", options: .regularExpression)
        rest = rest.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        rest = rest.replacingOccurrences(of: #"(?i)\b(or|and)\b|[,;*.]"#, with: " ", options: .regularExpression)
        return rest.split(whereSeparator: { $0.isWhitespace }).count <= 1
    }

    /// A heading that introduces choices: contains "Elective" (not "Unrestricted …" prose) or is "Option N". Returns
    /// the classes to pick: credit hours ÷ 3 when the heading gives them, the option's own size later, else 1.
    static func electiveHeading(_ line: String) -> Int? {
        guard codes(in: line).isEmpty, line.count <= 100, !line.hasSuffix(".") else { return nil }
        let lower = line.lowercased()
        let isOption = lower.range(of: #"^option\s+(\d+|[a-z])\b"#, options: .regularExpression) != nil
        guard isOption || lower.range(of: #"\belectives?\b"#, options: .regularExpression) != nil else { return nil }
        if lower.hasPrefix("note") || lower.contains(" may ") || lower.contains(" must ") { return nil }
        if let r = lower.range(of: #"\((\d+)(?:-\d+)?\s*(credit hours|credits|hours)\)"#, options: .regularExpression) {
            let n = Double(lower[r].filter(\.isNumber).prefix(2)) ?? 3
            return max(1, Int((n / 3).rounded(.up)))
        }
        return isOption ? 0 : 1
    }

    static func isStrongHeading(_ line: String) -> Bool {
        line.range(of: #"\(\d+(?:-\d+)?\s*(credit hours|credits|hours)\)\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil
            || (line.hasSuffix(":") && line.count <= 80) || line.lowercased().hasPrefix("total")
    }

    static func isHeading(_ line: String) -> Bool {
        if line.lowercased().hasPrefix("total") { return true }
        if line.range(of: #"\(\d+(?:-\d+)?\s*(credit hours|credits|hours)\)\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        if line.hasSuffix(":") && line.count <= 80 { return true }
        let words = line.split(separator: " ")
        if words.count <= 8, line.count <= 70, !line.hasSuffix("."), let first = line.first, first.isUppercase,
           words.filter({ $0.first?.isUppercase == true || $0.count <= 3 }).count == words.count {
            return true
        }
        return false
    }

    // MARK: DegreeWorks

    static func parseDegreeWorks(_ lines: [String]) -> ParsedDegreeDocument {
        var required: [DegreeItem] = []
        var choices: [DegreeChoiceGroup] = []
        var skipped: [String] = []
        var seen = Set<String>()
        var i = 0
        let need = try! NSRegularExpression(pattern: #"^(\d+)\s+(Class|Classes|Credit|Credits|Hour|Hours)\s+in\s+(.+)$"#, options: [.caseInsensitive])
        while i < lines.count {
            guard lines[i].hasPrefix("Still needed") else { i += 1; continue }
            let label = i > 0 ? requirementLabel(lines[i - 1]) : "Requirement"
            i += 1
            var pick = 1
            var byCredits = false
            var options: [String] = []
            var notes: [String] = []
            var subject: String?
            var started = false
            while i < lines.count {
                let line = lines[i]
                let ns = line as NSString
                if let m = need.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                    if started { break } // a second requirement in the same block
                    started = true
                    pick = Int(ns.substring(with: m.range(at: 1))) ?? 1
                    byCredits = ns.substring(with: m.range(at: 2)).lowercased().hasPrefix("credit") || ns.substring(with: m.range(at: 2)).lowercased().hasPrefix("hour")
                    appendOptions(ns.substring(with: m.range(at: 3)), into: &options, notes: &notes, subject: &subject)
                    i += 1
                    continue
                }
                if started, line.range(of: #"^(or|and)\s+"#, options: [.regularExpression, .caseInsensitive]) != nil {
                    appendOptions(String(line.drop { $0 != " " }), into: &options, notes: &notes, subject: &subject)
                    i += 1
                    continue
                }
                if started, line.lowercased().hasPrefix("additionally") || line.lowercased().hasPrefix("except") || line.lowercased().hasPrefix("including") {
                    notes.append(line)
                    i += 1
                    continue
                }
                break
            }
            guard started else {
                continue
            }
            let classes = byCredits ? max(1, Int((Double(pick) / 3).rounded(.up))) : pick
            let items = options.map { DegreeItem(code: $0, title: "", section: label) }
            if options.isEmpty {
                skipped.append("\(label): " + (notes.first ?? "a requirement with no listed classes"))
            } else if options.count == 1, classes == 1 {
                var item = items[0]
                item.title = label
                if seen.insert(item.code).inserted { required.append(item) }
            } else {
                choices.append(DegreeChoiceGroup(id: "choice-\(choices.count + 1)", label: label, pick: classes,
                                                 options: items.filter { seen.insert($0.code).inserted }, notes: notes))
            }
        }
        return ParsedDegreeDocument(kind: .degreeWorks, programName: nil, required: required, choices: choices, skippedLines: skipped)
    }

    /// "Introduction to Solid Mechanics Not complete Introduction to Solid Mechanics" → "Introduction to Solid Mechanics".
    static func requirementLabel(_ line: String) -> String {
        for marker in [" Not complete", " Requirement is complete", " When the in-progress classes", " INCOMPLETE", " Not Complete"] {
            if let range = line.range(of: marker) { return String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces) }
        }
        return line
    }

    /// "MEGR 3090", "3092", "BIOL 3161", "MEGR @", "MEGR 3@" → codes (subject carried over); wildcards become notes.
    static func appendOptions(_ text: String, into options: inout [String], notes: inout [String], subject: inout String?) {
        for piece in text.components(separatedBy: CharacterSet(charactersIn: ",")).flatMap({ $0.components(separatedBy: " or ") }) {
            let words = piece.split(separator: " ").map(String.init).filter { $0.lowercased() != "or" && $0.lowercased() != "and" }
            var j = 0
            while j < words.count {
                let w = words[j]
                if w.range(of: #"^[A-Z]{2,4}$"#, options: .regularExpression) != nil {
                    subject = w
                    if j + 1 < words.count, words[j + 1].contains("@") {
                        notes.append("Any \(w) \(words[j + 1] == "@" ? "class" : words[j + 1].replacingOccurrences(of: "@", with: "000-level class"))")
                        j += 2
                        continue
                    }
                } else if w.range(of: #"^\d{4}[A-Z]?$"#, options: .regularExpression) != nil, let subject {
                    let code = "\(subject) \(w)"
                    if !options.contains(code) { options.append(code) }
                } else if w.contains("@"), let subject {
                    notes.append("Any \(subject) \(w == "@" ? "class" : w.replacingOccurrences(of: "@", with: "000-level class"))")
                }
                j += 1
            }
        }
    }
}
