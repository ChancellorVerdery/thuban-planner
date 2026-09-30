import Foundation

/// One Rate My Professors school page. Only the UNC Charlotte pages in `RateMyProfessors.unccSchools` are ever
/// queried.
public struct RMPSchool: Codable, Hashable, Sendable, Identifiable {
    /// GraphQL node id (base64 of "School-<legacyId>").
    public var id: String
    public var legacyId: Int
    public var name: String

    public init(id: String, legacyId: Int, name: String) {
        self.id = id
        self.legacyId = legacyId
        self.name = name
    }

    public var pageURL: URL { URL(string: "https://www.ratemyprofessors.com/school/\(legacyId)")! }
}

/// Constants for Rate My Professors (RMP).
///
/// Research (2026-09-30, live, read-only GraphQL `newSearch { schools }` for "UNC Charlotte", "University of North
/// Carolina at Charlotte", "UNCC", "UNC-Charlotte", "UNC at Charlotte", "North Carolina at Charlotte", "Charotte",
/// "Charlotte" …): RMP has exactly TWO pages for UNC Charlotte —
/// - 1253 "University of North Carolina at Charlotte" (Matthews, NC; 913 school ratings; the page every
///   professor is on), and
/// - 19352 "University of North Carolina at Charotte" (sic; Charlotte, NC; 0 school ratings, no professors yet).
/// Both are searched for every professor; a professor found on both is combined (weighted by number of ratings).
/// Everything else named "Charlotte" (Queens University of Charlotte, Charlotte School of Law, …) is a different
/// school.
public enum RateMyProfessors {
    public static let host = "www.ratemyprofessors.com"
    public static let endpoint = URL(string: "https://www.ratemyprofessors.com/graphql")!
    /// RMP's public web client sends this fixed header (`test:test`); it is not a user credential.
    public static let publicAuthorization = "Basic dGVzdDp0ZXN0"

    public static let unccMain = RMPSchool(id: "U2Nob29sLTEyNTM=", legacyId: 1253, name: "University of North Carolina at Charlotte")
    public static let unccAlternate = RMPSchool(id: "U2Nob29sLTE5MzUy", legacyId: 19352, name: "University of North Carolina at Charotte")
    /// Every UNC Charlotte page, main first. The only schools the app may query.
    public static let unccSchools: [RMPSchool] = [unccMain, unccAlternate]

    public static func school(legacyId: Int) -> RMPSchool? { unccSchools.first { $0.legacyId == legacyId } }
    public static func school(id: String) -> RMPSchool? { unccSchools.first { $0.id == id } }

    /// "https://www.ratemyprofessors.com/professor/<legacyId>".
    public static func professorURL(legacyId: Int) -> URL {
        URL(string: "https://www.ratemyprofessors.com/professor/\(legacyId)")!
    }

    /// RMP's own professor search, scoped to the main UNC Charlotte page.
    public static func searchURL(name: String, school: RMPSchool = unccMain) -> URL {
        var components = URLComponents(string: "https://www.ratemyprofessors.com/search/professors/\(school.legacyId)")!
        components.queryItems = [URLQueryItem(name: "q", value: name)]
        return components.url!
    }
}

/// A professor profile on one RMP school page (`newSearch.teachers.edges[].node`).
public struct RMPTeacher: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var legacyId: Int
    public var firstName: String
    public var lastName: String
    public var department: String
    /// 0 when there are no ratings.
    public var avgRating: Double
    public var avgDifficulty: Double
    public var numRatings: Int
    /// -1 = unknown (no rating answered the question).
    public var wouldTakeAgainPercent: Double
    public var schoolId: String
    public var schoolLegacyId: Int
    public var schoolName: String

    public init(id: String, legacyId: Int, firstName: String, lastName: String, department: String = "", avgRating: Double = 0,
                avgDifficulty: Double = 0, numRatings: Int = 0, wouldTakeAgainPercent: Double = -1,
                school: RMPSchool = RateMyProfessors.unccMain) {
        self.id = id
        self.legacyId = legacyId
        self.firstName = firstName
        self.lastName = lastName
        self.department = department
        self.avgRating = avgRating
        self.avgDifficulty = avgDifficulty
        self.numRatings = numRatings
        self.wouldTakeAgainPercent = wouldTakeAgainPercent
        self.schoolId = school.id
        self.schoolLegacyId = school.legacyId
        self.schoolName = school.name
    }

    /// "Ritchie Dudley" (white space collapsed).
    public var displayName: String {
        BannerText.collapse("\(firstName) \(lastName)")
    }

    public var profileURL: URL { RateMyProfessors.professorURL(legacyId: legacyId) }

    /// Nil when unknown.
    public var wouldTakeAgain: Double? { wouldTakeAgainPercent >= 0 && numRatings > 0 ? wouldTakeAgainPercent : nil }
}

/// A professor's rating, combined over every matching UNC Charlotte profile: averages weighted by number of ratings.
public struct RMPRating: Codable, Hashable, Sendable {
    /// Matching profiles, most ratings first.
    public var profiles: [RMPTeacher]
    /// Σ numRatings.
    public var numRatings: Int
    /// Σ(avgRating × n) / Σ n over profiles with ratings; nil when nobody rated them.
    public var avgRating: Double?
    public var avgDifficulty: Double?
    /// Weighted by n over profiles with ratings AND a known would-take-again value; nil when none.
    public var wouldTakeAgainPercent: Double?

    public init(profiles: [RMPTeacher]) {
        let sorted = profiles.sorted { $0.numRatings != $1.numRatings ? $0.numRatings > $1.numRatings : $0.legacyId < $1.legacyId }
        self.profiles = sorted
        let rated = sorted.filter { $0.numRatings > 0 }
        let total = rated.reduce(0) { $0 + $1.numRatings }
        numRatings = total
        if total > 0 {
            avgRating = rated.reduce(0.0) { $0 + $1.avgRating * Double($1.numRatings) } / Double(total)
            avgDifficulty = rated.reduce(0.0) { $0 + $1.avgDifficulty * Double($1.numRatings) } / Double(total)
        } else {
            avgRating = nil
            avgDifficulty = nil
        }
        let known = rated.filter { $0.wouldTakeAgainPercent >= 0 }
        let knownTotal = known.reduce(0) { $0 + $1.numRatings }
        wouldTakeAgainPercent = knownTotal > 0
            ? known.reduce(0.0) { $0 + $1.wouldTakeAgainPercent * Double($1.numRatings) } / Double(knownTotal)
            : nil
    }

    /// Distinct UNC Charlotte pages the profiles are on.
    public var schoolCount: Int { Set(profiles.map(\.schoolLegacyId)).count }

    public var isCombined: Bool { profiles.count > 1 }

    /// "Combined from 2 UNC Charlotte pages, weighted by number of ratings" / "… from 2 profiles …"; nil for one.
    public var combinedDescription: String? {
        guard isCombined else { return nil }
        if schoolCount > 1 { return "Combined from \(schoolCount) UNC Charlotte pages, weighted by number of ratings" }
        return "Combined from \(profiles.count) profiles on UNC Charlotte’s page, weighted by number of ratings"
    }
}

/// What a lookup concluded for one instructor of one course.
public enum RMPMatch: Hashable, Sendable {
    case found(RMPRating)
    /// Several different UNC Charlotte professors fit the name; no score is shown.
    case ambiguous([RMPTeacher])
    case notFound
}
