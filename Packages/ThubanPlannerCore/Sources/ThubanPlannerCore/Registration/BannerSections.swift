import Foundation

/// A weekday as Banner's meeting flags name them. Raw values run Monday = 1 … Sunday = 7.
public enum BannerWeekday: Int, Codable, CaseIterable, Sendable, Comparable, Identifiable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    public var id: Int { rawValue }
    public static func < (a: BannerWeekday, b: BannerWeekday) -> Bool { a.rawValue < b.rawValue }

    /// "Mon".
    public var shortLabel: String {
        switch self {
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        case .sunday: return "Sun"
        }
    }

    /// Registrar letters: M T W R F S U.
    public var letter: String {
        switch self {
        case .monday: return "M"
        case .tuesday: return "T"
        case .wednesday: return "W"
        case .thursday: return "R"
        case .friday: return "F"
        case .saturday: return "S"
        case .sunday: return "U"
        }
    }

    public var fullLabel: String {
        switch self {
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        case .sunday: return "Sunday"
        }
    }

    /// The JSON key Banner uses for the flag ("monday").
    var bannerKey: String {
        switch self {
        case .monday: return "monday"
        case .tuesday: return "tuesday"
        case .wednesday: return "wednesday"
        case .thursday: return "thursday"
        case .friday: return "friday"
        case .saturday: return "saturday"
        case .sunday: return "sunday"
        }
    }
}

/// One meeting pattern of a section (`meetingsFaculty[].meetingTime`). A section may have several (lecture + a
/// recitation hour, a hybrid's evening session …). Times are minutes after midnight; nil = no set time (online /
/// TBA). Dates are `yyyyMMdd` integers so ranges compare numerically; nil = the whole term.
public struct BannerMeeting: Codable, Hashable, Sendable {
    public var days: [BannerWeekday]
    public var begin: Int?
    public var end: Int?
    public var startDate: Int?
    public var endDate: Int?
    public var building: String?
    public var buildingDescription: String?
    public var room: String?
    /// "Class", "Exam" …
    public var meetingType: String?
    /// "LC", "LB" …
    public var scheduleType: String?

    public init(days: [BannerWeekday], begin: Int?, end: Int?, startDate: Int? = nil, endDate: Int? = nil,
                building: String? = nil, buildingDescription: String? = nil, room: String? = nil,
                meetingType: String? = nil, scheduleType: String? = nil) {
        self.days = days.sorted()
        self.begin = begin
        self.end = end
        self.startDate = startDate
        self.endDate = endDate
        self.building = building
        self.buildingDescription = buildingDescription
        self.room = room
        self.meetingType = meetingType
        self.scheduleType = scheduleType
    }

    /// Has days and a real [begin, end) interval — the only meetings that can conflict or appear on the grid.
    public var isTimed: Bool {
        guard let begin, let end, end > begin, !days.isEmpty else { return false }
        return true
    }

    /// "DUKE 276" (building code + room), or the building alone, or nil.
    public var location: String? {
        switch (building?.isEmpty == false ? building : nil, room?.isEmpty == false ? room : nil) {
        case let (b?, r?): return "\(b) \(r)"
        case let (b?, nil): return b
        case let (nil, r?): return r
        default: return nil
        }
    }

    /// "MWF 9:05–9:55 AM" style summary (or "No set time").
    public var summary: String {
        guard isTimed, let begin, let end else { return days.isEmpty ? "No set time" : "\(days.map(\.letter).joined()) · no set time" }
        return "\(days.map(\.letter).joined()) \(BannerClock.range(begin, end))"
    }

    /// True when both ranges share at least one day of the calendar (inclusive; a missing bound means open-ended).
    public func datesOverlap(_ other: BannerMeeting) -> Bool {
        let aStart = startDate ?? Int.min, aEnd = endDate ?? Int.max
        let bStart = other.startDate ?? Int.min, bEnd = other.endDate ?? Int.max
        return aStart <= bEnd && bStart <= aEnd
    }

    /// Two timed meetings conflict when they share a weekday, their [begin, end) times overlap and their date
    /// ranges overlap.
    public func conflicts(with other: BannerMeeting) -> Bool {
        guard isTimed, other.isTimed, let b1 = begin, let e1 = end, let b2 = other.begin, let e2 = other.end else { return false }
        guard b1 < e2, b2 < e1 else { return false }
        guard days.contains(where: other.days.contains) else { return false }
        return datesOverlap(other)
    }
}

/// A class section from Banner's class search (`searchResults/searchResults` `data[]`), normalized.
public struct BannerSection: Codable, Hashable, Sendable, Identifiable {
    /// CRN, e.g. "20263".
    public var crn: String
    public var term: String
    public var subject: String
    public var courseNumber: String
    /// "001", "L01", "C02".
    public var sequenceNumber: String
    public var title: String
    /// "Lecture", "Laboratory" …
    public var scheduleType: String
    /// "Face-to-Face Instruction", "Hybrid: F2F & Online (Sync)" (white space collapsed).
    public var instructionalMethod: String
    public var campus: String
    /// `creditHours` ?? `creditHourLow` (nil when Banner gives neither).
    public var credits: Double?
    /// May be negative (over-enrolled).
    public var seatsAvailable: Int
    public var maximumEnrollment: Int
    public var enrollment: Int
    public var waitCapacity: Int
    public var waitCount: Int
    public var waitAvailable: Int
    /// Banner's own flag (unreliable — `seatsAvailable` is what the filters use).
    public var openSection: Bool
    public var isLinked: Bool
    public var linkIdentifier: String?
    public var partOfTerm: String?
    /// Instructor display names, primary first (often empty for future terms).
    public var instructors: [String]
    public var meetings: [BannerMeeting]

    public var id: String { crn }

    public init(crn: String, term: String, subject: String, courseNumber: String, sequenceNumber: String, title: String,
                scheduleType: String = "Lecture", instructionalMethod: String = "Face-to-Face Instruction",
                campus: String = "Main Campus", credits: Double? = 3, seatsAvailable: Int = 10, maximumEnrollment: Int = 40,
                enrollment: Int = 30, waitCapacity: Int = 0, waitCount: Int = 0, waitAvailable: Int = 0, openSection: Bool = true,
                isLinked: Bool = false, linkIdentifier: String? = nil, partOfTerm: String? = "1", instructors: [String] = [],
                meetings: [BannerMeeting]) {
        self.crn = crn
        self.term = term
        self.subject = subject
        self.courseNumber = courseNumber
        self.sequenceNumber = sequenceNumber
        self.title = title
        self.scheduleType = scheduleType
        self.instructionalMethod = instructionalMethod
        self.campus = campus
        self.credits = credits
        self.seatsAvailable = seatsAvailable
        self.maximumEnrollment = maximumEnrollment
        self.enrollment = enrollment
        self.waitCapacity = waitCapacity
        self.waitCount = waitCount
        self.waitAvailable = waitAvailable
        self.openSection = openSection
        self.isLinked = isLinked
        self.linkIdentifier = linkIdentifier
        self.partOfTerm = partOfTerm
        self.instructors = instructors
        self.meetings = meetings
    }

    /// "MEGR 2144".
    public var courseCode: String { "\(subject) \(courseNumber)" }

    public var timedMeetings: [BannerMeeting] { meetings.filter(\.isTimed) }

    /// No meeting with a set time: online asynchronous or "TBA". Never conflicts; listed apart from the grid.
    public var hasNoSetTime: Bool { timedMeetings.isEmpty }

    /// Online in the "allow online" filter's sense: no set time, or an online method that is not hybrid / F2F.
    public var isOnline: Bool {
        if hasNoSetTime { return true }
        let method = instructionalMethod.lowercased()
        return method.contains("online") && !method.contains("hybrid") && !method.contains("f2f") && !method.contains("face")
    }

    /// Seats > 0.
    public var hasOpenSeat: Bool { seatsAvailable > 0 }

    /// Full (no seat) or somebody is already waiting.
    public var isFullOrWaitlisted: Bool { seatsAvailable <= 0 || waitCount > 0 }

    /// Every timed meeting of both sections, pairwise.
    public func conflicts(with other: BannerSection) -> Bool {
        for a in timedMeetings { for b in other.timedMeetings where a.conflicts(with: b) { return true } }
        return false
    }

    /// Short description of the times, "MWF 9:05–9:55 AM · TR 10:10–11:00 AM" (or "Online / TBA").
    public var timeSummary: String {
        let timed = timedMeetings
        return timed.isEmpty ? "Online / TBA" : timed.map(\.summary).joined(separator: " · ")
    }
}

/// `searchResults/searchResults` response.
public struct BannerSearchPage: Sendable, Equatable {
    public var totalCount: Int
    public var sections: [BannerSection]
    public var success: Bool

    public init(totalCount: Int, sections: [BannerSection], success: Bool = true) {
        self.totalCount = totalCount
        self.sections = sections
        self.success = success
    }

    /// Decodes a search page. Throws when the body is not JSON (e.g. an HTML login page).
    public static func decode(_ data: Data) throws -> BannerSearchPage {
        let root: JSONValue
        do { root = try JSONValue.parse(data) } catch {
            throw ThubanError.decoding("The class search did not return JSON.")
        }
        guard root.isObject else { throw ThubanError.decoding("The class search returned an unexpected shape.") }
        let rows = root["data"]?.arrayValue ?? []
        let sections = rows.compactMap(BannerSectionDecoder.section)
        return BannerSearchPage(totalCount: root["totalCount"]?.bannerInt ?? sections.count, sections: sections,
                                success: root["success"]?.bannerBool ?? true)
    }
}

/// `searchResults/fetchLinkedSections` → `{linkedData: [[section, …], …]}`: each inner list is one set of sections
/// that must be taken together with the section asked about.
public enum BannerLinkedSections {
    public static func decode(_ data: Data) throws -> [[BannerSection]] {
        let root: JSONValue
        do { root = try JSONValue.parse(data) } catch { throw ThubanError.decoding("Linked sections did not return JSON.") }
        guard let sets = root["linkedData"]?.arrayValue else { return [] }
        return sets.compactMap { set -> [BannerSection]? in
            let sections = (set.arrayValue ?? [set]).compactMap(BannerSectionDecoder.section)
            return sections.isEmpty ? nil : sections
        }
    }
}

enum BannerSectionDecoder {
    static func section(_ row: JSONValue) -> BannerSection? {
        guard row.isObject, let crn = row["courseReferenceNumber"]?.bannerString, !crn.isEmpty else { return nil }
        let subject = row["subject"]?.bannerString ?? ""
        let number = row["courseNumber"]?.bannerString ?? row["courseDisplay"]?.bannerString ?? ""
        var faculty: [(String, Bool)] = []
        for f in row["faculty"]?.arrayValue ?? [] {
            if let name = f["displayName"]?.bannerString, !name.isEmpty {
                faculty.append((BannerText.collapse(name), f["primaryIndicator"]?.bannerBool ?? false))
            }
        }
        // Primary first, otherwise Banner's order; no duplicates.
        var instructors: [String] = []
        for (name, _) in faculty.filter({ $0.1 }) + faculty.filter({ !$0.1 }) where !instructors.contains(name) { instructors.append(name) }
        let meetings = (row["meetingsFaculty"]?.arrayValue ?? []).compactMap { entry -> BannerMeeting? in
            let mt = entry["meetingTime"] ?? entry
            guard mt.isObject else { return nil }
            return meeting(mt)
        }
        let credits = row["creditHours"]?.bannerDouble ?? row["creditHourLow"]?.bannerDouble ?? row["creditHourHigh"]?.bannerDouble
        let link = row["linkIdentifier"]?.bannerString.flatMap { $0.isEmpty ? nil : $0 }
        return BannerSection(
            crn: crn,
            term: row["term"]?.bannerString ?? "",
            subject: subject,
            courseNumber: number,
            sequenceNumber: row["sequenceNumber"]?.bannerString ?? "",
            title: BannerText.collapse(row["courseTitle"]?.bannerString ?? ""),
            scheduleType: BannerText.collapse(row["scheduleTypeDescription"]?.bannerString ?? ""),
            instructionalMethod: BannerText.collapse(row["instructionalMethodDescription"]?.bannerString ?? ""),
            campus: BannerText.collapse(row["campusDescription"]?.bannerString ?? ""),
            credits: credits,
            seatsAvailable: row["seatsAvailable"]?.bannerInt ?? 0,
            maximumEnrollment: row["maximumEnrollment"]?.bannerInt ?? 0,
            enrollment: row["enrollment"]?.bannerInt ?? 0,
            waitCapacity: row["waitCapacity"]?.bannerInt ?? 0,
            waitCount: row["waitCount"]?.bannerInt ?? 0,
            waitAvailable: row["waitAvailable"]?.bannerInt ?? 0,
            openSection: row["openSection"]?.bannerBool ?? false,
            isLinked: row["isSectionLinked"]?.bannerBool ?? false,
            linkIdentifier: link,
            partOfTerm: row["partOfTerm"]?.bannerString,
            instructors: instructors,
            meetings: meetings)
    }

    static func meeting(_ mt: JSONValue) -> BannerMeeting {
        let days = BannerWeekday.allCases.filter { mt[$0.bannerKey]?.bannerBool == true }
        func text(_ key: String) -> String? {
            guard let s = mt[key]?.bannerString else { return nil }
            let c = BannerText.collapse(s)
            return c.isEmpty ? nil : c
        }
        return BannerMeeting(days: days,
                             begin: mt["beginTime"]?.bannerString.flatMap(BannerClock.minutes),
                             end: mt["endTime"]?.bannerString.flatMap(BannerClock.minutes),
                             startDate: mt["startDate"]?.bannerString.flatMap(BannerClock.dateNumber),
                             endDate: mt["endDate"]?.bannerString.flatMap(BannerClock.dateNumber),
                             building: text("building"), buildingDescription: text("buildingDescription"), room: text("room"),
                             meetingType: text("meetingTypeDescription"), scheduleType: text("meetingScheduleType"))
    }
}

/// Clock and date helpers.
public enum BannerClock {
    /// "0905" → 545; "905" → 545; "13:30" → 810. Nil for anything else.
    public static func minutes(_ text: String) -> Int? {
        let digits = text.filter(\.isNumber)
        guard (3...4).contains(digits.count), let value = Int(digits) else { return nil }
        let h = value / 100, m = value % 100
        guard h < 24 || (h == 24 && m == 0), m < 60 else { return nil }
        return h * 60 + m
    }

    /// "MM/dd/yyyy" → yyyyMMdd (e.g. 20270111); also accepts "yyyy-MM-dd".
    public static func dateNumber(_ text: String) -> Int? {
        let parts = text.split(whereSeparator: { $0 == "/" || $0 == "-" }).map(String.init)
        guard parts.count == 3, let a = Int(parts[0]), let b = Int(parts[1]), let c = Int(parts[2]) else { return nil }
        let (y, m, d) = parts[0].count == 4 ? (a, b, c) : (c, a, b)
        guard (1...12).contains(m), (1...31).contains(d), y > 1900 else { return nil }
        return y * 10000 + m * 100 + d
    }

    /// 545 → "9:05 AM"; 810 → "1:30 PM".
    public static func label(_ minutes: Int, withPeriod: Bool = true) -> String {
        let h = (minutes / 60) % 24, m = minutes % 60
        let h12 = h % 12 == 0 ? 12 : h % 12
        let base = String(format: "%d:%02d", h12, m)
        return withPeriod ? "\(base) \(h < 12 ? "AM" : "PM")" : base
    }

    /// "9:05–9:55 AM", "11:15 AM–12:05 PM".
    public static func range(_ begin: Int, _ end: Int) -> String {
        let samePeriod = (begin / 60 < 12) == (end / 60 < 12)
        return samePeriod ? "\(label(begin, withPeriod: false))–\(label(end))" : "\(label(begin))–\(label(end))"
    }

    /// "9 AM", "12 PM", "3 PM" for grid hour labels.
    public static func hourLabel(_ hour: Int) -> String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(h12) \(hour % 24 < 12 ? "AM" : "PM")"
    }
}
