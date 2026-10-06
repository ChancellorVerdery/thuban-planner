import Foundation

/// A deterministic, realistic mechanical-engineering degree for the smoke screenshots and
/// `THUBAN_PLANNER_SEED=sample`: four recorded past terms plus the current term (placed relative to `now`), 43
/// classes (29 taken or in progress, 14 to take) with prerequisite chains, lecture ↔ lab corequisite pairs, a few
/// summer-offered classes, one requirement naming a class that is not in the plan (STAT 3128), and the next summer
/// switched off (an internship). Settings: 16 credits, summer 7, "Graduate soonest (use summers)".
public enum SampleData {
    public static func make(now: Date = Date(), calendar: Calendar = .current) -> PlannerData {
        // Current term = the calendar term containing `now`; the four recorded past terms are the fall / spring
        // terms before it (summers skipped).
        let current = TermKey.current(now: now, calendar: calendar)
        var past: [String] = []
        var cursor = current
        while past.count < 4 {
            cursor = TermKey.previous(cursor)
            if TermKey.season(cursor) != .summer { past.insert(cursor, at: 0) }
        }
        let termKeys = past + [current]
        let terms = termKeys.enumerated().map { index, key -> Term in
            let p = TermKey.parse(key)
            return Term(season: p.season ?? .fall, year: p.year, current: index == termKeys.count - 1)
        }

        var courses: [Course] = []
        func add(_ code: String, _ title: String, _ credits: Double, pre: [String] = [], co: [String] = [], summer: Bool = false, term: Int? = nil) {
            courses.append(Course(id: String(format: "c-sample-%02d", courses.count + 1), code: code, title: title, credits: credits,
                                  prereqs: pre, coreqs: co, summerOk: summer, term: term.map { termKeys[$0] }))
        }

        // Year one, first term
        add("ENGR 1201", "Introduction to Engineering I", 2, term: 0)
        add("MATH 1241", "Calculus I", 3, summer: true, term: 0)
        add("CHEM 1251", "General Chemistry I", 3, co: ["CHEM 1251L"], summer: true, term: 0)
        add("CHEM 1251L", "General Chemistry I Lab", 1, co: ["CHEM 1251"], summer: true, term: 0)
        add("ENGL 1101", "Writing and Inquiry I", 3, summer: true, term: 0)
        add("LBST 1101", "Arts and Society: Film", 3, summer: true, term: 0)
        // Year one, second term
        add("ENGR 1202", "Introduction to Engineering II", 2, pre: ["ENGR 1201"], term: 1)
        add("MATH 1242", "Calculus II", 3, pre: ["MATH 1241"], summer: true, term: 1)
        add("PHYS 2101", "Physics for Engineers I", 3, pre: ["MATH 1241"], co: ["PHYS 2101L"], summer: true, term: 1)
        add("PHYS 2101L", "Physics I Lab", 1, co: ["PHYS 2101"], summer: true, term: 1)
        add("ENGL 2116", "Technical Communication", 3, pre: ["ENGL 1101"], summer: true, term: 1)
        add("ECON 2101", "Principles of Macroeconomics", 3, summer: true, term: 1)
        // Year two, first term
        add("MATH 2241", "Calculus III", 3, pre: ["MATH 1242"], summer: true, term: 2)
        add("PHYS 2102", "Physics for Engineers II", 3, pre: ["PHYS 2101", "MATH 1242"], co: ["PHYS 2102L"], term: 2)
        add("PHYS 2102L", "Physics II Lab", 1, co: ["PHYS 2102"], term: 2)
        add("MEGR 2141", "Engineering Mechanics I: Statics", 3, pre: ["PHYS 2101"], co: ["MATH 2241"], term: 2)
        add("MEGR 2156", "Engineering Graphics and CAD", 3, pre: ["ENGR 1202"], term: 2)
        add("LBST 2102", "Global Connections", 3, summer: true, term: 2)
        // Year two, second term
        add("MATH 2171", "Differential Equations", 3, pre: ["MATH 1242"], summer: true, term: 3)
        add("MEGR 2144", "Introduction to Solid Mechanics", 3, pre: ["MEGR 2141"], term: 3)
        add("MEGR 2240", "Computational Methods for Engineers", 3, pre: ["MATH 1242", "ENGR 1202"], term: 3)
        add("ECGR 2111", "Network Theory I", 3, pre: ["PHYS 2102"], co: ["MATH 2171"], term: 3)
        add("LBST 2213", "Science, Technology and Society", 3, summer: true, term: 3)
        // Current term
        add("MEGR 3111", "Thermodynamics I", 3, pre: ["MATH 2241", "PHYS 2101"], term: 4)
        add("MEGR 3121", "Dynamics Systems I", 3, pre: ["MEGR 2141", "MATH 2171"], term: 4)
        add("MEGR 3161", "Introduction to Engineering Materials", 3, pre: ["CHEM 1251", "MEGR 2144"], term: 4)
        add("MEGR 3171", "Instrumentation and Measurements", 2, pre: ["ECGR 2111"], co: ["MEGR 3171L"], term: 4)
        add("MEGR 3171L", "Instrumentation Lab", 1, co: ["MEGR 3171"], term: 4)
        add("COMM 1101", "Public Speaking", 3, summer: true, term: 4)
        // Still to take
        add("MEGR 3112", "Thermodynamics II", 3, pre: ["MEGR 3111"])
        add("MEGR 3114", "Fluid Mechanics", 3, pre: ["MEGR 3111", "MEGR 3121"])
        add("MEGR 3116", "Heat Transfer", 3, pre: ["MEGR 3114", "MATH 2171"])
        add("MEGR 3211", "Thermal-Fluids Laboratory", 1, pre: ["MEGR 3114"], co: ["MEGR 3116"])
        add("MEGR 3122", "Dynamic Systems II", 3, pre: ["MEGR 3121", "MEGR 2240"])
        add("MEGR 3152", "Design of Machine Elements", 3, pre: ["MEGR 2144", "MEGR 3161"])
        add("MEGR 3162", "Manufacturing Processes", 3, pre: ["MEGR 3161"], summer: true)
        add("MEGR 3090", "Senior Design I", 3, pre: ["MEGR 3152", "MEGR 3114", "MEGR 3122"])
        add("MEGR 3092", "Senior Design II", 3, pre: ["MEGR 3090"])
        add("MEGR 4125", "Mechanical Vibrations", 3, pre: ["MEGR 3122"])
        add("MEGR 4150", "Composite Materials", 3, pre: ["MEGR 3161"], summer: true)
        add("ENGR 3295", "Engineering Economics", 3, pre: ["STAT 3128"], summer: true)
        add("MATH 2164", "Matrices and Linear Algebra", 3, pre: ["MATH 1242"], summer: true)
        add("PHIL 3527", "Ethics in Engineering", 3, summer: true)

        // The next summer after the current term is an internship.
        var nextSummer = TermKey.next(current)
        while TermKey.season(nextSummer) != .summer { nextSummer = TermKey.next(nextSummer) }

        return PlannerData(courses: courses, terms: terms, disabledTerms: [nextSummer],
                           settings: PlannerSettings(maxCredits: 16, summerMax: 7, strategy: .soonestSummer))
    }

    /// `make` plus transfer credit, for the transfer smoke scenes: three AP / community-college classes appended
    /// (`c-sample-t1…t3`, so the other ids are unchanged) — STAT 3128 (the class ENGR 3295 names, so a ribbon runs
    /// from the transfer column), PSYC 1101 and HIST 1110 — and MATH 2164 (`c-sample-42`) moved to transfer.
    public static func makeWithTransferCredit(now: Date = Date(), calendar: Calendar = .current) -> PlannerData {
        var data = make(now: now, calendar: calendar)
        data.courses.append(Course(id: "c-sample-t1", code: "STAT 3128", title: "Probability & Statistics for Engineers",
                                   credits: 3, summerOk: true, term: TermKey.transfer))
        data.courses.append(Course(id: "c-sample-t2", code: "PSYC 1101", title: "General Psychology (AP)", credits: 3,
                                   summerOk: true, term: TermKey.transfer))
        data.courses.append(Course(id: "c-sample-t3", code: "HIST 1110", title: "U.S. History to 1865 (AP)", credits: 3,
                                   summerOk: true, term: TermKey.transfer))
        data.moveToTransfer(["c-sample-42"])
        return data
    }
}
