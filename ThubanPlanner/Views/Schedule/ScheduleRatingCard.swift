import AppKit
import SwiftUI
import ThubanPlannerCore

/// One instructor in the class detail sheet: name, then their Rate My Professors state — loading, the (combined)
/// rating with difficulty / would-take-again / count and profile links, a per-page breakdown when several UNC
/// Charlotte profiles were combined, "no ratings yet", ambiguous (candidates with links, no score), not on RMP (a
/// search link), or failed (Try again).
struct ScheduleRatingCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var rawName: String
    var subject: String
    var isPrimary: Bool

    private var name: RMPPersonName? { RMPPersonName.parse(rawName) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name?.displayName ?? rawName)
                    .font(ThubanFont.display(19))
                    .foregroundStyle(theme.inkColor)
                if isPrimary { Chip("Primary", kind: .neutral) }
                Spacer(minLength: 6)
                if let name, app.scheduleTab.ratings.isRefreshing(name), case .loaded? = app.scheduleTab.ratings.lookup(name) {
                    ProgressView().controlSize(.mini)
                }
                Text("Rate My Professors")
                    .font(ThubanFont.body(11.5, weight: .semibold))
                    .foregroundStyle(theme.inkFaintColor)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bgColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
    }

    @ViewBuilder
    private var content: some View {
        let ratings = app.scheduleTab.ratings
        if let name {
            switch ratings.lookup(name) {
            case nil, .loading?:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Looking up \(name.displayName) at UNC Charlotte…")
                        .font(ThubanFont.body(13))
                        .foregroundStyle(theme.inkDimColor)
                }
                .frame(minHeight: 44)
            case .failed(let message)?:
                VStack(alignment: .leading, spacing: 10) {
                    Text(message)
                        .font(ThubanFont.body(13))
                        .foregroundStyle(theme.negTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button { ratings.request(name, force: true) } label: {
                            HStack(spacing: 6) { Icon(.history, size: 14); Text("Try again") }
                        }
                        .buttonStyle(SecondaryButtonStyle(height: 30))
                        linkButton("Search Rate My Professors", url: RateMyProfessors.searchURL(name: name.displayName), primary: false)
                    }
                }
            case .loaded(let candidates)?:
                switch RMPMatcher.match(name: name, candidates: candidates, subject: subject) {
                case .found(let rating): found(rating, name: name)
                case .ambiguous(let list): ambiguous(list, name: name)
                case .notFound: notFound(name)
                }
            }
        }
    }

    // MARK: Found

    @ViewBuilder
    private func found(_ rating: RMPRating, name: RMPPersonName) -> some View {
        if let avg = rating.avgRating {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 22) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", avg))
                            .font(ThubanFont.display(40))
                            .foregroundStyle(tone(avg))
                            .monospacedDigit()
                        Text("/ 5")
                            .font(ThubanFont.body(15, weight: .medium))
                            .foregroundStyle(theme.inkFaintColor)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(format: "Overall rating %.1f out of 5", avg))
                    Rectangle().fill(theme.lineColor).frame(width: 1, height: 44)
                    stat("\(rating.numRatings)", rating.numRatings == 1 ? "rating" : "ratings")
                    stat(rating.avgDifficulty.map { String(format: "%.1f", $0) } ?? "—", "difficulty / 5")
                    stat(rating.wouldTakeAgainPercent.map { String(format: "%.0f%%", $0) } ?? "—", "would take again")
                    Spacer(minLength: 0)
                }
                if let combined = rating.combinedDescription {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(combined)
                            .font(ThubanFont.body(12, weight: .medium))
                            .foregroundStyle(theme.brassInkColor)
                            .padding(.bottom, 6)
                        ForEach(rating.profiles) { profile in
                            Hairline()
                            profileRow(profile)
                        }
                    }
                } else if let profile = rating.profiles.first {
                    HStack(spacing: 10) {
                        Text([profile.department, Self.shortSchool(profile)].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(ThubanFont.body(12))
                            .foregroundStyle(theme.inkDimColor)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        linkButton("Open on Rate My Professors", url: profile.profileURL, primary: true)
                    }
                }
            }
        } else {
            // On RMP, but nobody has rated them.
            VStack(alignment: .leading, spacing: 8) {
                Text("On Rate My Professors, but no ratings yet")
                    .font(ThubanFont.body(14, weight: .semibold))
                    .foregroundStyle(theme.inkColor)
                ForEach(rating.profiles) { profile in
                    HStack(spacing: 10) {
                        Text([profile.department, Self.shortSchool(profile)].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(ThubanFont.body(12))
                            .foregroundStyle(theme.inkDimColor)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        linkButton("Open on Rate My Professors", url: profile.profileURL, primary: false)
                    }
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(ThubanFont.body(18, weight: .semibold))
                .foregroundStyle(theme.inkColor)
                .monospacedDigit()
            Text(label)
                .font(ThubanFont.body(11.5))
                .foregroundStyle(theme.inkFaintColor)
        }
        .accessibilityElement(children: .combine)
    }

    /// One profile of a combined rating: page, department, its own rating × count, link.
    private func profileRow(_ profile: RMPTeacher) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.schoolName)
                    .font(ThubanFont.body(12.5, weight: .medium))
                    .foregroundStyle(theme.inkColor)
                    .lineLimit(1)
                Text([profile.displayName, profile.department].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(ThubanFont.body(11.5))
                    .foregroundStyle(theme.inkFaintColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(profile.numRatings > 0 ? String(format: "%.1f", profile.avgRating) : "—")
                .font(ThubanFont.mono(13, weight: .semibold))
                .foregroundStyle(profile.numRatings > 0 ? tone(profile.avgRating) : theme.inkFaintColor)
                .frame(width: 34, alignment: .trailing)
            Text("\(profile.numRatings) rating\(profile.numRatings == 1 ? "" : "s")")
                .font(ThubanFont.body(12))
                .foregroundStyle(theme.inkDimColor)
                .monospacedDigit()
                .frame(width: 74, alignment: .trailing)
            linkButton("Open", url: profile.profileURL, primary: false)
        }
        .padding(.vertical, 7)
    }

    // MARK: Ambiguous / not found

    private func ambiguous(_ list: [RMPTeacher], name: RMPPersonName) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Several UNC Charlotte professors could be “\(name.displayName)” — no score is shown. Open the one who teaches this class:")
                .font(ThubanFont.body(13))
                .foregroundStyle(theme.inkDimColor)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
            ForEach(list.prefix(6)) { profile in
                Hairline()
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.displayName)
                            .font(ThubanFont.body(13, weight: .semibold))
                            .foregroundStyle(theme.inkColor)
                        Text([profile.department, "\(profile.numRatings) rating\(profile.numRatings == 1 ? "" : "s")"].filter { !$0.isEmpty }
                            .joined(separator: " · "))
                            .font(ThubanFont.body(11.5))
                            .foregroundStyle(theme.inkFaintColor)
                    }
                    Spacer(minLength: 8)
                    linkButton("Open", url: profile.profileURL, primary: false)
                }
                .padding(.vertical, 7)
            }
        }
    }

    private func notFound(_ name: RMPPersonName) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("No Rate My Professors page at UNC Charlotte")
                    .font(ThubanFont.body(14, weight: .semibold))
                    .foregroundStyle(theme.inkColor)
                Text("Searched both UNC Charlotte pages for \(name.displayName).")
                    .font(ThubanFont.body(12))
                    .foregroundStyle(theme.inkDimColor)
            }
            Spacer(minLength: 8)
            linkButton("Search Rate My Professors", url: RateMyProfessors.searchURL(name: name.displayName), primary: false)
        }
    }

    // MARK: Pieces

    /// "UNC Charlotte" for the main page; the second page keeps its (misspelled) RMP name.
    static func shortSchool(_ profile: RMPTeacher) -> String {
        profile.schoolLegacyId == RateMyProfessors.unccMain.legacyId ? "UNC Charlotte" : profile.schoolName
    }

    private func tone(_ rating: Double) -> Color {
        rating >= 4 ? theme.posTextColor : (rating >= 3 ? theme.brassInkColor : theme.negTextColor)
    }

    /// Opens `url` in the default browser.
    @ViewBuilder
    private func linkButton(_ title: String, url: URL, primary: Bool) -> some View {
        let button = Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 6) {
                Text(title)
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold))
            }
        }
        Group {
            if primary {
                button.buttonStyle(SecondaryButtonStyle(height: 30))
            } else {
                button.buttonStyle(GhostButtonStyle(height: 28, tinted: true, horizontalPadding: 8))
            }
        }
        .fixedSize()
        .help(url.absoluteString)
        .accessibilityLabel("\(title) (opens in your browser)")
    }
}
