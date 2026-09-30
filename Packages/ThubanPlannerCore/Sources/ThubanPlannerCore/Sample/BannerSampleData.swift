import Foundation

/// Deterministic, realistic Banner data for smoke screenshots and previews (no network): a term list around a
/// given term, and 3–6 sections per course code with UNC Charlotte-style meeting patterns, rooms and seats.
public enum BannerSampleData {
    /// Six terms, newest first, around `centerKey` (the one after it, it, and four before).
    public static func terms(around centerKey: String) -> [BannerTerm] {
        var keys = [TermKey.next(centerKey), centerKey]
        var cursor = centerKey
        while keys.count < 6 { cursor = TermKey.previous(cursor); keys.append(cursor) }
        return keys.compactMap { key in
            guard let code = BannerTermCode.code(forTermKey: key) else { return nil }
            return BannerTerm(code: code, description: TermKey.label(key), viewOnly: key != centerKey && key != TermKey.next(centerKey))
        }
    }

    private static let patterns: [(days: [BannerWeekday], begin: Int, end: Int)] = [
        ([.monday, .wednesday, .friday], 8 * 60, 8 * 60 + 50),
        ([.monday, .wednesday, .friday], 9 * 60 + 5, 9 * 60 + 55),
        ([.monday, .wednesday, .friday], 10 * 60 + 10, 11 * 60),
        ([.monday, .wednesday, .friday], 11 * 60 + 15, 12 * 60 + 5),
        ([.monday, .wednesday], 13 * 60 + 25, 14 * 60 + 40),
        ([.tuesday, .thursday], 8 * 60 + 30, 9 * 60 + 45),
        ([.tuesday, .thursday], 10 * 60, 11 * 60 + 15),
        ([.tuesday, .thursday], 11 * 60 + 30, 12 * 60 + 45),
        ([.tuesday, .thursday], 13 * 60, 14 * 60 + 15),
        ([.tuesday, .thursday], 14 * 60 + 30, 15 * 60 + 45),
        ([.monday, .wednesday], 16 * 60, 17 * 60 + 15),
        ([.tuesday, .thursday], 17 * 60 + 30, 18 * 60 + 45),
    ]
    private static let buildings = ["DUKE", "EPIC", "GRIGG", "CAMERON", "BURSON", "WOODWARD", "FRETWELL"]
    private static let instructors = ["Harish Cherukuri", "Alireza Tabarraei", "Jun Xu", "Terry Xu", "Nate Fried", "Katie Gordon", "Umesh Silwal"]

    /// FNV-1a: stable across launches (Swift's `Hasher` is seeded per process).
    static func stableHash(_ text: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 { h ^= UInt64(byte); h = h &* 0x100000001b3 }
        return h
    }

    /// Sections for one course. Lab codes ("…L") get one 2 h 45 min weekly meeting; a course-number ending "90"
    /// (e.g. senior design) gets an online section.
    public static func sections(course code: String, title: String, credits: Double = 3, termCode: String) -> [BannerSection] {
        guard let split = BannerText.splitCourseCode(code) else { return [] }
        let h = stableHash(code)
        let isLab = split.number.hasSuffix("L")
        let count = 3 + Int(h % 4)
        let year = Int(termCode.prefix(4)) ?? 2027
        let season = BannerTermCode.season(ofSuffix: String(termCode.suffix(2))) ?? .spring
        let (start, end): (Int, Int) = {
            switch season {
            case .spring: return (year * 10000 + 111, year * 10000 + 506)
            case .summer: return (year * 10000 + 518, year * 10000 + 806)
            case .fall: return (year * 10000 + 817, year * 10000 + 1210)
            }
        }()
        let subjectBase = Int(stableHash(split.subject) % 9) * 1000
        return (0..<count).map { i in
            let pick = Int((h >> UInt64(4 + i * 5)) % UInt64(patterns.count))
            var meetingPattern = patterns[(pick + i * 5) % patterns.count]
            if isLab {
                let day = BannerWeekday(rawValue: 1 + (pick + i) % 5) ?? .monday
                let begins = [8 * 60 + 30, 11 * 60 + 30, 14 * 60 + 30, 17 * 60 + 30]
                let begin = begins[(pick + i) % begins.count]
                meetingPattern = ([day], begin, begin + 165)
            }
            let seatsRaw = Int((h >> UInt64(i * 3)) % 40) - 6
            let online = !isLab && split.number.hasSuffix("90") && i == count - 1
            let building = buildings[Int((h >> UInt64(i * 2)) % UInt64(buildings.count))]
            let meeting = online
                ? BannerMeeting(days: [], begin: nil, end: nil, startDate: start, endDate: end, meetingType: "Class")
                : BannerMeeting(days: meetingPattern.days, begin: meetingPattern.begin, end: meetingPattern.end, startDate: start, endDate: end,
                                building: building, buildingDescription: building.capitalized, room: String(100 + Int((h >> UInt64(i)) % 300)),
                                meetingType: "Class", scheduleType: isLab ? "LB" : "LC")
            return BannerSection(
                crn: String(20000 + subjectBase + Int(h % 700) + i * 7),
                term: termCode, subject: split.subject, courseNumber: split.number,
                sequenceNumber: isLab ? String(format: "L%02d", i + 1) : String(format: "%03d", i + 1),
                title: title, scheduleType: isLab ? "Laboratory" : "Lecture",
                instructionalMethod: online ? "Online (Asynchronous)" : "Face-to-Face Instruction",
                campus: "Main Campus", credits: credits,
                seatsAvailable: seatsRaw, maximumEnrollment: isLab ? 24 : 60, enrollment: max(0, (isLab ? 24 : 60) - seatsRaw),
                waitCapacity: 10, waitCount: seatsRaw <= 0 ? Int(h % 5) : 0, waitAvailable: 10,
                openSection: seatsRaw > 0,
                instructors: [instructors[Int((h >> UInt64(i + 7)) % UInt64(instructors.count))]],
                meetings: [meeting])
        }
    }
}
