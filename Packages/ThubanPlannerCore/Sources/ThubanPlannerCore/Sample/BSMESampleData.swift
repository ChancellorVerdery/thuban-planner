import Foundation

/// A fictional UNC Charlotte BSME (2025-26 catalog) student midway through the degree, for the technical-elective and
/// degree-import smoke scenes and tests: the common first year and physics done (PHYS 1101L standing in for PHYS
/// 2101L, as a transfer AP credit does), Fall 2026 current, the rest of the major core still to take, no technical
/// electives yet. Real catalog codes, titles, credits and prerequisites.
public enum BSMESampleData {
    public static func make() -> PlannerData {
        var courses: [Course] = []
        func add(_ code: String, _ title: String, _ credits: Double, pre: [String] = [], co: [String] = [], summer: Bool = false, term: String? = nil) {
            courses.append(Course(id: String(format: "c-bsme-%02d", courses.count + 1), code: code, title: title, credits: credits,
                                  prereqs: pre, coreqs: co, summerOk: summer, term: term))
        }
        // Fall 2025
        add("ENGR 1300", "Exploring Engineering & Technology with Success", 2, term: "fall-2025")
        add("ENGR 1302", "Logic and Computational Problem Solving", 3, term: "fall-2025")
        add("ENGR 1303", "Engineering Visualization and Graphical Communication", 3, term: "fall-2025")
        add("MATH 1241", "Calculus I", 3, term: "fall-2025")
        add("WRDS 1103", "Writing and Inquiry in Academic Contexts", 3, term: "fall-2025")
        add("PHYS 1101L", "Introductory Physics I Laboratory", 1, term: "fall-2025")
        // Spring 2026
        add("PHYS 2101", "Physics for Science and Engineering I", 3, pre: ["MATH 1241"], co: ["PHYS 1101L"], term: "spring-2026")
        add("MEGR 2152", "CAD for Mechanical Engineers", 1, pre: ["ENGR 1303"], term: "spring-2026")
        add("CTCM 2530", "Critical Thinking and Communication", 3, pre: ["WRDS 1103"], term: "spring-2026")
        add("HIST 1575", "American Democracy", 3, term: "spring-2026")
        // Summer 2026
        add("MATH 1242", "Calculus II", 3, pre: ["MATH 1241"], term: "summer-2026")
        add("PHYS 2102", "Physics for Science and Engineering II", 3, pre: ["PHYS 2101", "MATH 1242"], co: ["PHYS 2102L"], term: "summer-2026")
        add("PHYS 2102L", "Physics for Science and Engineering II Laboratory", 1, pre: ["PHYS 1101L"], co: ["PHYS 2102"], term: "summer-2026")
        // Fall 2026 (current)
        add("ENGR 1301", "Foundations of Math and Science for Engineering", 3, term: "fall-2026")
        add("MATH 2171", "Differential Equations", 3, pre: ["MATH 1242"], term: "fall-2026")
        add("MATH 2241", "Calculus III", 3, pre: ["MATH 1242"], term: "fall-2026")
        add("MEGR 2141", "Engineering Mechanics I", 3, pre: ["PHYS 2101", "MATH 1242"], term: "fall-2026")
        add("MEGR 3111", "Thermodynamics I", 3, pre: ["MATH 1242", "PHYS 2101"], term: "fall-2026")
        // Still to take
        add("MEGR 2144", "Introduction to Solid Mechanics", 3, pre: ["MEGR 2141"], summer: true)
        add("MEGR 2157", "Design Projects I Laboratory", 3, pre: ["ENGR 1300", "MEGR 2141", "MEGR 2152"], co: ["MEGR 2180"], summer: true)
        add("MEGR 2180", "Manufacturing Systems", 3, pre: ["MEGR 2141"], co: ["MEGR 2157"], summer: true)
        add("MEGR 2173", "Mechatronics I", 2, pre: ["ENGR 1302", "PHYS 2102"], co: ["MEGR 2174"])
        add("MEGR 2174", "Mechatronics I Projects Laboratory", 1, pre: ["PHYS 2102L"], co: ["MEGR 2173"])
        add("MEGR 2233", "Math and Science for Engineers II", 3, pre: ["ENGR 1301", "MATH 1241"], summer: true)
        add("MEGR 2234", "Math and Science for Engineers III", 4, pre: ["MEGR 2233", "MATH 2171"])
        add("MEGR 2242", "Computational Methods for Engineers", 2, pre: ["MEGR 2233"], summer: true)
        add("MEGR 3114", "Fluid Mechanics", 3, pre: ["MEGR 3121", "MATH 2241"], summer: true)
        add("MEGR 3116", "Introduction to Heat Transfer", 3, pre: ["MATH 2171", "MEGR 3111"], co: ["MEGR 3114"], summer: true)
        add("MEGR 3121", "Dynamics Systems I", 3, pre: ["MEGR 2141", "MATH 1242"], summer: true)
        add("MEGR 3123", "Dynamic Systems II", 2, pre: ["MEGR 3121", "MEGR 2234", "MEGR 2242"])
        add("MEGR 3152", "Mechanics and Materials Laboratory", 2, pre: ["MEGR 2144", "MEGR 3174"], co: ["MEGR 3161"], summer: true)
        add("MEGR 3156", "Design Projects Lab II", 2, pre: ["MEGR 2144", "MEGR 2157", "MEGR 2173", "MEGR 2174", "MEGR 2180"], summer: true)
        add("MEGR 3161", "Introduction to Engineering Materials", 3, pre: ["MEGR 2144", "MEGR 2233"], summer: true)
        add("MEGR 3173", "Mechatronics II", 2, pre: ["MEGR 2173"], co: ["MEGR 3174"], summer: true)
        add("MEGR 3174", "Mechatronics II Projects Laboratory", 1, pre: ["MEGR 2174"], co: ["MEGR 3173"], summer: true)
        add("MEGR 3221", "Machine Analysis and Design I", 3, pre: ["MEGR 2144", "MEGR 3121"])
        add("MEGR 3251", "Thermal/Fluids Laboratory", 2, pre: ["MEGR 3111", "MEGR 3174", "MEGR 3114"], summer: true)
        add("MEGR 3255", "Senior Design I", 2, pre: ["MEGR 3111", "MEGR 3114", "MEGR 3161", "MEGR 3174", "MEGR 3156"], co: ["MEGR 3152", "MEGR 3251"])
        add("MEGR 3256", "Senior Design II", 2, pre: ["MEGR 3255"])
        add("ENGR 3295", "Multidisciplinary Professional Development", 1)

        let terms = [
            Term(season: .fall, year: 2025, current: false),
            Term(season: .spring, year: 2026, current: false),
            Term(season: .summer, year: 2026, current: false),
            Term(season: .fall, year: 2026, current: true),
        ]
        return PlannerData(courses: courses, terms: terms, disabledTerms: ["summer-2027"],
                           settings: PlannerSettings(maxCredits: 15, summerMax: 9, strategy: .soonestOptionalSummer, minCredits: 12))
    }
}
