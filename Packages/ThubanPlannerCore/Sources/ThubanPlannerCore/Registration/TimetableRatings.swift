import Foundation

/// Professor ratings for the "Highest professor rating" timetable sort, built by the app from the Rate My
/// Professors cache (the generator stays pure: it only reads this value).
public struct TimetableRatings: Hashable, Sendable {
    /// CRN → the section's professor rating (1–5): the primary instructor's combined UNC Charlotte rating; with
    /// several rated instructors, their mean weighted by number of ratings. Sections without a usable rating are
    /// absent.
    public var bySection: [String: Double]

    public init(bySection: [String: Double] = [:]) { self.bySection = bySection }

    public static let empty = TimetableRatings()

    public var isEmpty: Bool { bySection.isEmpty }

    /// The numRatings-weighted mean of the ratings that have any ratings; nil when none do.
    public static func sectionRating(_ ratings: [RMPRating]) -> Double? {
        let rated = ratings.filter { $0.numRatings > 0 && $0.avgRating != nil }
        let total = rated.reduce(0) { $0 + $1.numRatings }
        guard total > 0 else { return nil }
        return rated.reduce(0.0) { $0 + ($1.avgRating ?? 0) * Double($1.numRatings) } / Double(total)
    }

    /// Builds the table for `sections`: `match(instructor, section)` says what RMP knows about one instructor (nil =
    /// not looked up yet). Only `.found` with ratings counts — not on RMP, 0 ratings, ambiguous and unassigned
    /// instructors are left out.
    public static func build(sections: [BannerSection], match: (String, BannerSection) -> RMPMatch?) -> TimetableRatings {
        var table: [String: Double] = [:]
        for section in sections where table[section.crn] == nil {
            let found = section.instructors.compactMap { name -> RMPRating? in
                if case .found(let rating)? = match(name, section) { return rating }
                return nil
            }
            if let value = sectionRating(found) { table[section.crn] = value }
        }
        return TimetableRatings(bySection: table)
    }

    /// A timetable's professor score.
    public struct Score: Hashable, Sendable {
        /// Σ(rating × credits) / Σ credits over the rated courses.
        public var value: Double
        public var ratedCourses: Int
        public var ratedCredits: Double
    }

    /// Credit-weighted over the courses whose chosen section has a rating; the credits of a linked set are its first
    /// (lecture) section's, counted once, and its rating the first rated section's. Courses without a rating (or
    /// without credits) contribute neither. Nil when no course is rated.
    public func score(_ option: TimetableOption) -> Score? {
        var weighted = 0.0, credits = 0.0, courses = 0
        for pick in option.picks {
            guard let rating = pick.choice.sections.lazy.compactMap({ self.bySection[$0.crn] }).first,
                  let cr = pick.choice.sections.first?.credits, cr > 0 else { continue }
            weighted += rating * cr
            credits += cr
            courses += 1
        }
        guard credits > 0 else { return nil }
        return Score(value: weighted / credits, ratedCourses: courses, ratedCredits: credits)
    }
}
