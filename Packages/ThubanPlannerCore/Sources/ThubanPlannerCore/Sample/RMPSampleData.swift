import Foundation

/// Fictional Rate My Professors profiles for the offline smoke run and previews — the instructors of
/// `BannerSampleData`. No network. Covers: a professor on BOTH UNC Charlotte pages (combined), single profiles,
/// a duplicate profile with 0 ratings, a professor with no ratings yet, an ambiguous initial ("Chen, L."), and one
/// who is not on RMP ("Priya Raman").
public enum RMPSampleData {
    private static func t(_ legacy: Int, _ first: String, _ last: String, _ dept: String, _ rating: Double, _ difficulty: Double,
                          _ count: Int, _ again: Double, _ school: RMPSchool = RateMyProfessors.unccMain) -> RMPTeacher {
        RMPTeacher(id: "sample-\(legacy)", legacyId: legacy, firstName: first, lastName: last, department: dept, avgRating: rating,
                   avgDifficulty: difficulty, numRatings: count, wouldTakeAgainPercent: again, school: school)
    }

    static let table: [String: [RMPTeacher]] = [
        "dana whitfield": [t(9_000_101, "Dana", "Whitfield", "Mechanical Engineering", 4.4, 2.9, 38, 88.2),
                           t(9_000_102, "Dana", "Whitfield", "Engineering", 3.6, 3.4, 12, -1, RateMyProfessors.unccAlternate)],
        "marcus oyelaran": [t(9_000_201, "Marcus", "Oyelaran", "Mathematics", 3.1, 3.8, 57, 52)],
        "l chen": [t(9_000_301, "Li", "Chen", "Physics", 3.9, 2.7, 41, 80), t(9_000_302, "Lin", "Chen", "Mathematics", 2.8, 3.9, 19, 40)],
        "priya raman": [],
        "elena brandt": [t(9_000_401, "Elena", "Brandt", "Engineering", 4.7, 2.4, 22, 95)],
        "tomas reyes": [t(9_000_501, "Tomas", "Reyes", "Physics", 3.5, 3.1, 9, 67), t(9_000_502, "Tomás", "Reyes", "Physics", 0, 0, 0, -1)],
        "grace okafor": [t(9_000_601, "Grace", "Okafor", "Mechanical Engineering", 2.6, 4.2, 31, 35)],
        "owen lindqvist": [t(9_000_701, "Owen", "Lindqvist", "Engineering", 0, 0, 0, -1)],
    ]

    /// The cached candidates for a sample name ([] = not on RMP).
    public static func candidates(for name: RMPPersonName) -> [RMPTeacher] {
        (table[name.key] ?? []).filter { RMPMatcher.isCandidate(name, $0) }
    }
}
