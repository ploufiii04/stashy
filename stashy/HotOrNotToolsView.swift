//
//  HotOrNotToolsView.swift
//  stashy
//
//  Duel modes Swiss / Gauntlet / Champion + leaderboard, aligned with the HotOrNot Stash plugin
//  (hotornot_stats, rating100, performer_record; math from hot_or_not.js / math-utils.js).
//

#if !os(tvOS)
import Foundation
import SwiftUI

// MARK: - Plugin-compatible stats

private struct HotOrNotStats: Codable, Equatable {
    var total_matches: Int
    var wins: Int
    var losses: Int
    var draws: Int
    var current_streak: Int
    var best_streak: Int
    var worst_streak: Int
    var last_match: String?

    init(
        total_matches: Int,
        wins: Int,
        losses: Int,
        draws: Int,
        current_streak: Int,
        best_streak: Int,
        worst_streak: Int,
        last_match: String?
    ) {
        self.total_matches = total_matches
        self.wins = wins
        self.losses = losses
        self.draws = draws
        self.current_streak = current_streak
        self.best_streak = best_streak
        self.worst_streak = worst_streak
        self.last_match = last_match
    }

    static let empty = HotOrNotStats(
        total_matches: 0, wins: 0, losses: 0, draws: 0,
        current_streak: 0, best_streak: 0, worst_streak: 0, last_match: nil
    )

    enum CodingKeys: String, CodingKey {
        case total_matches, wins, losses, draws, current_streak, best_streak, worst_streak, last_match
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total_matches = try c.decodeIfPresent(Int.self, forKey: .total_matches) ?? 0
        wins = try c.decodeIfPresent(Int.self, forKey: .wins) ?? 0
        losses = try c.decodeIfPresent(Int.self, forKey: .losses) ?? 0
        draws = try c.decodeIfPresent(Int.self, forKey: .draws) ?? 0
        current_streak = try c.decodeIfPresent(Int.self, forKey: .current_streak) ?? 0
        best_streak = try c.decodeIfPresent(Int.self, forKey: .best_streak) ?? 0
        worst_streak = try c.decodeIfPresent(Int.self, forKey: .worst_streak) ?? 0
        last_match = try c.decodeIfPresent(String.self, forKey: .last_match)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(total_matches, forKey: .total_matches)
        try c.encode(wins, forKey: .wins)
        try c.encode(losses, forKey: .losses)
        try c.encode(draws, forKey: .draws)
        try c.encode(current_streak, forKey: .current_streak)
        try c.encode(best_streak, forKey: .best_streak)
        try c.encode(worst_streak, forKey: .worst_streak)
        try c.encodeIfPresent(last_match, forKey: .last_match)
    }
}

private struct HotOrNotMatchRecord: Codable, Equatable {
    let date: String
    let opponent: String
    let won: Bool?
    let ratingAfter: Int
}

// MARK: - Math (matches plugin math-utils.js)

private enum HotOrNotSwissMath {

    static func parseStats(from customFields: [String: StashJSONValue]?) -> HotOrNotStats {
        guard let fields = customFields else { return .empty }
        if case .string(let json) = fields["hotornot_stats"],
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(HotOrNotStats.self, from: data) {
            return decoded
        }
        if case .string(let elo) = fields["elo_matches"], let n = Int(elo) {
            var s = HotOrNotStats.empty
            s.total_matches = n
            return s
        }
        return .empty
    }

    static func recencyWeight(stats: HotOrNotStats) -> Double {
        guard let raw = stats.last_match else { return 0.7 }
        let d = Self.isoParser.date(from: raw)
            ?? Self.isoParserPlain.date(from: raw)
        guard let d else { return 0.7 }
        let hours = Date().timeIntervalSince(d) / 3600
        return min(1, 1 - exp(-0.2 * hours))
    }

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoParserPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func weightedPick<T>(items: [T], weights: [Double]) -> T? {
        guard items.count == weights.count, !items.isEmpty else { return nil }
        let total = weights.reduce(0, +)
        if total <= 0 { return items.randomElement() }
        var r = Double.random(in: 0..<total)
        for (i, w) in weights.enumerated() {
            r -= w
            if r <= 0 { return items[i] }
        }
        return items.last
    }

    /// Plugin `getKFactor`: halved K only for `mode == "champion"`; `"gauntlet"` uses same base as Swiss.
    static func getKFactor(currentRating: Double, matchCount: Int?, mode: String) -> Int {
        let baseK: Int
        if let mc = matchCount {
            baseK = mc < 10 ? 16 : (mc < 30 ? 12 : 8)
        } else {
            let dist = abs(currentRating - 50)
            baseK = dist < 10 ? 12 : (dist < 25 ? 10 : 8)
        }
        return mode == "champion" ? max(1, Int(round(Double(baseK) * 0.5))) : baseK
    }

    /// Swiss or Champion full ELO on both sides (`calculateMatchOutcome` non-gauntlet branch in hot_or_not.js).
    static func outcomeRatedMatch(
        winnerRating: Double,
        loserRating: Double,
        winnerMatchCount: Int,
        loserMatchCount: Int,
        eloMode: String
    ) -> (winnerGain: Int, loserLoss: Int) {
        let ratingDiff = loserRating - winnerRating
        let expectedWinner = 1 / (1 + pow(10, ratingDiff / 400))
        let wK = Double(getKFactor(currentRating: winnerRating, matchCount: winnerMatchCount, mode: eloMode))
        let lK = Double(getKFactor(currentRating: loserRating, matchCount: loserMatchCount, mode: eloMode))
        let winnerGain = max(0, Int(round(wK * (1 - expectedWinner))))
        let loserLoss = max(0, Int(round(lK * expectedWinner)))
        return (winnerGain, loserLoss)
    }

    static func outcomeSwiss(
        winnerRating: Double,
        loserRating: Double,
        winnerMatchCount: Int,
        loserMatchCount: Int
    ) -> (winnerGain: Int, loserLoss: Int) {
        outcomeRatedMatch(
            winnerRating: winnerRating,
            loserRating: loserRating,
            winnerMatchCount: winnerMatchCount,
            loserMatchCount: loserMatchCount,
            eloMode: "swiss"
        )
    }

    static func outcomeChampion(
        winnerRating: Double,
        loserRating: Double,
        winnerMatchCount: Int,
        loserMatchCount: Int
    ) -> (winnerGain: Int, loserLoss: Int) {
        outcomeRatedMatch(
            winnerRating: winnerRating,
            loserRating: loserRating,
            winnerMatchCount: winnerMatchCount,
            loserMatchCount: loserMatchCount,
            eloMode: "champion"
        )
    }

    /// Gauntlet selective ELO (`calculateMatchOutcome` when `mode === "gauntlet"` in plugin).
    static func outcomeGauntlet(
        winnerRating: Double,
        loserRating: Double,
        winnerMatchCount: Int,
        isChampionWinner: Bool,
        isFallingWinner: Bool,
        isChampionLoser: Bool,
        isFallingLoser: Bool,
        loserRank: Int?
    ) -> (winnerGain: Int, loserLoss: Int) {
        let ratingDiff = loserRating - winnerRating
        let expectedWinner = 1 / (1 + pow(10, ratingDiff / 400))
        var winnerGain = 0
        var loserLoss = 0
        let k = Double(getKFactor(currentRating: winnerRating, matchCount: winnerMatchCount, mode: "gauntlet"))
        if isChampionWinner || isFallingWinner {
            winnerGain = max(0, Int(round(k * (1 - expectedWinner))))
        }
        if isChampionLoser || isFallingLoser {
            loserLoss = max(0, Int(round(k * expectedWinner)))
        }
        if let r = loserRank, r == 1, !isChampionLoser, !isFallingLoser {
            loserLoss = 1
        }
        return (winnerGain, loserLoss)
    }

    /// Draw / skip: same roles as plugin handleSkip (isDraw): left = winner id, right = loser id.
    static func outcomeDraw(
        leftRating: Double,
        rightRating: Double,
        leftMatches: Int,
        rightMatches: Int
    ) -> (leftGain: Int, rightLoss: Int) {
        let ratingDiff = rightRating - leftRating
        let expectedWinner = 1 / (1 + pow(10, ratingDiff / 400))
        let wK = Double(getKFactor(currentRating: leftRating, matchCount: leftMatches, mode: "swiss"))
        let lK = Double(getKFactor(currentRating: rightRating, matchCount: rightMatches, mode: "swiss"))
        let leftGain = Int(round(wK * (0.5 - expectedWinner)))
        let rightLoss = Int(round(lK * (1 - expectedWinner - 0.5)))
        return (leftGain, rightLoss)
    }

    static func updateStats(_ current: HotOrNotStats, won: Bool?) -> HotOrNotStats {
        var n = current
        n.total_matches = (current.total_matches) + 1
        n.last_match = Self.nowISO()
        if won == nil {
            n.draws = (current.draws) + 1
            return n
        }
        if won == true {
            n.wins = (current.wins) + 1
            if current.current_streak >= 0 {
                n.current_streak = (current.current_streak) + 1
            } else {
                n.current_streak = 1
            }
        } else {
            n.losses = (current.losses) + 1
            if current.current_streak <= 0 {
                n.current_streak = (current.current_streak) - 1
            } else {
                n.current_streak = -1
            }
        }
        n.best_streak = max(current.best_streak, n.current_streak)
        n.worst_streak = min(current.worst_streak, n.current_streak)
        return n
    }

    private static func nowISO() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    static func encodeStats(_ s: HotOrNotStats) throws -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return String(data: try enc.encode(s), encoding: .utf8) ?? "{}"
    }

    static func parseMatchRecords(from customFields: [String: StashJSONValue]?) -> [HotOrNotMatchRecord] {
        guard let fields = customFields,
              case .string(let raw) = fields["performer_record"],
              let data = raw.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([HotOrNotMatchRecord].self, from: data)) ?? []
    }

    static func encodeMatchRecords(_ records: [HotOrNotMatchRecord]) throws -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return String(data: try enc.encode(records), encoding: .utf8) ?? "[]"
    }
}

// MARK: - GraphQL response types

private struct HotOrNotPerformerData: Codable {
    let id: String
    let name: String
    let disambiguation: String?
    let birthdate: String?
    let country: String?
    let image_path: String?
    let scene_count: Int?
    let image_count: Int?
    let gallery_count: Int?
    let gender: String?
    let ethnicity: String?
    let height_cm: Int?
    let weight: Int?
    let measurements: String?
    let fake_tits: String?
    let penis_length: Double?
    let career_length: String?
    let tattoos: String?
    let piercings: String?
    let alias_list: [String]?
    let favorite: Bool?
    let rating100: Int?
    let o_counter: Int?
    let custom_fields: [String: StashJSONValue]?

    var stats: HotOrNotStats { HotOrNotSwissMath.parseStats(from: custom_fields) }

    var displayName: String {
        if let d = disambiguation, !d.isEmpty { return "\(name) (\(d))" }
        return name
    }

    /// Minimal `Performer` for pushing `PerformerDetailView` from Hot or Not (detail loads full data).
    func toPerformerStub() -> Performer {
        Performer(
            id: id,
            name: name,
            disambiguation: disambiguation,
            birthdate: birthdate,
            country: country,
            imagePath: image_path,
            sceneCount: scene_count ?? 0,
            galleryCount: gallery_count,
            gender: gender,
            ethnicity: ethnicity,
            height: height_cm,
            weight: weight,
            measurements: measurements,
            fakeTits: fake_tits,
            penis_length: penis_length,
            careerLength: career_length,
            tattoos: tattoos,
            piercings: piercings,
            aliasList: alias_list,
            favorite: favorite,
            rating100: rating100,
            createdAt: nil,
            updatedAt: nil,
            oCounter: o_counter
        )
    }

    func replacingRating100(_ newRating: Int) -> HotOrNotPerformerData {
        HotOrNotPerformerData(
            id: id,
            name: name,
            disambiguation: disambiguation,
            birthdate: birthdate,
            country: country,
            image_path: image_path,
            scene_count: scene_count,
            image_count: image_count,
            gallery_count: gallery_count,
            gender: gender,
            ethnicity: ethnicity,
            height_cm: height_cm,
            weight: weight,
            measurements: measurements,
            fake_tits: fake_tits,
            penis_length: penis_length,
            career_length: career_length,
            tattoos: tattoos,
            piercings: piercings,
            alias_list: alias_list,
            favorite: favorite,
            rating100: newRating,
            o_counter: o_counter,
            custom_fields: custom_fields
        )
    }
}

/// Fixed 3×2 grid for battle cards: same fields always; empty → "—".
private func hotOrNotBattleFixedInfoRows(_ p: HotOrNotPerformerData) -> [(label: String, value: String)] {
    let dash = "—"
    let rating = "\(p.rating100 ?? 50)"
    let genderVal: String = {
        guard let g = p.gender?.trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty else { return dash }
        return g
    }()
    let scenesVal = "\(p.scene_count ?? 0)"
    let imagesVal = "\(p.image_count ?? 0)"
    let countryVal: String = {
        guard let c = p.country?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty else { return dash }
        return c
    }()
    let titsVal: String = {
        let g = p.gender?.uppercased() ?? ""
        if g.contains("FEMALE") {
            if let t = p.fake_tits?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
            return dash
        }
        if g.contains("MALE") || g == "MAN" {
            if let pl = p.penis_length, pl > 0 { return String(format: "%.0f cm", pl) }
            return dash
        }
        if let t = p.fake_tits?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        if let pl = p.penis_length, pl > 0 { return String(format: "%.0f cm", pl) }
        return dash
    }()
    return [
        ("RATING", rating),
        ("GENDER", genderVal),
        ("SCENES", scenesVal),
        ("IMAGES", imagesVal),
        ("COUNTRY", countryVal),
        ("TITS", titsVal)
    ]
}

/// Clips the performer photo: only the **top** corners match the card radius; the **bottom** edge stays square (no rounding).
private struct HotOrNotPhotoTopClipShape: Shape {
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, rect.width * 0.5, rect.height * 0.5)
        var p = Path()
        guard r > 0 else {
            p.addRect(rect)
            return p
        }
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.minY + r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        p.closeSubpath()
        return p
    }
}

/// Row above each duel column; opens `PerformerDetailView` (label is only “Profile”).
private struct HotOrNotProfileLinkCard: View {
    let performer: HotOrNotPerformerData

    var body: some View {
        NavigationLink {
            PerformerDetailView(performer: performer.toPerformerStub())
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.3")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Profile")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
                .background(Color.secondaryAppBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
                .cardShadow()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile, \(performer.displayName)")
    }
}

private struct HotOrNotBattleColumn: View {
    @ObservedObject var model: HotOrNotViewModel
    let performer: HotOrNotPerformerData
    let rank: Int?
    let voteFeedback: HotOrNotDuelVoteFeedback.Side?
    let choose: () -> Void

    private var rows: [(label: String, value: String)] {
        hotOrNotBattleFixedInfoRows(performer)
    }

    private var cardCornerRadius: CGFloat { DesignTokens.CornerRadius.card }

    var body: some View {
        Button(action: choose) {
            ZStack {
                VStack(alignment: .leading, spacing: 0) {
                    photoStack
                    VStack(alignment: .leading, spacing: 8) {
                        nameBlock
                        detailGrid
                    }
                    .padding(10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondaryAppBackground)
                .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cardCornerRadius)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )

                if let vote = voteFeedback {
                    RoundedRectangle(cornerRadius: cardCornerRadius)
                        .fill(voteTint(for: vote.delta100))
                    VStack(spacing: 6) {
                        Text(signedDeltaText(vote.delta100))
                            .font(.system(size: 30, weight: .heavy))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        Text("Score")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .textCase(.uppercase)
                        Text("\(vote.rating100After)")
                            .font(.title2.monospacedDigit().weight(.bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    }
                    .padding(.horizontal, 8)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius))
            .cardShadow()
        }
        .buttonStyle(.plain)
        .disabled(model.isSubmitting)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Choose \(performer.displayName)")
    }

    private func voteTint(for delta100: Int) -> Color {
        if delta100 > 0 { return Color.green.opacity(0.42) }
        if delta100 < 0 { return Color.red.opacity(0.42) }
        return Color.gray.opacity(0.35)
    }

    private func signedDeltaText(_ delta100: Int) -> String {
        if delta100 > 0 { return "+\(delta100)" }
        return "\(delta100)"
    }

    private var photoStack: some View {
        let r = cardCornerRadius
        return ZStack(alignment: .topTrailing) {
            GeometryReader { geo in
                ZStack {
                    Color.gray.opacity(DesignTokens.Opacity.placeholder)
                    photoOverlay
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            }
            .aspectRatio(3 / 4, contentMode: .fit)
            rankBadge
        }
        .clipShape(HotOrNotPhotoTopClipShape(cornerRadius: r))
    }

    @ViewBuilder
    private var photoOverlay: some View {
        if let url = model.thumbnailURL(for: performer) {
            CustomAsyncImage(url: url) { loader in
                if loader.isLoading {
                    ProgressView()
                } else if let image = loader.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholderIcon
                }
            }
        } else {
            placeholderIcon
        }
    }

    private var placeholderIcon: some View {
        Image(systemName: "person.fill")
            .font(.largeTitle)
            .foregroundStyle(Color.appAccent.opacity(0.45))
    }

    @ViewBuilder
    private var rankBadge: some View {
        if let rank {
            Text("#\(rank)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.primary)
                .padding(6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(8)
        }
    }

    private var nameBlock: some View {
        Text(performer.displayName)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.primary)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, detail in
                VStack(alignment: .leading, spacing: 0) {
                    Text(detail.label)
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    Text(detail.value)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Gauntlet starter: same card shell as duel (`HotOrNotBattleColumn`), but only photo + name + rating row (no detail grid, no rank).
private struct HotOrNotGauntletStarterPickCard: View {
    @ObservedObject var model: HotOrNotViewModel
    let performer: HotOrNotPerformerData
    let onPick: () -> Void

    private var ratingText: String {
        "\(performer.rating100 ?? 50)"
    }

    private var cardCornerRadius: CGFloat { DesignTokens.CornerRadius.card }

    var body: some View {
        Button(action: onPick) {
            VStack(alignment: .leading, spacing: 0) {
                photoStack
                VStack(alignment: .leading, spacing: 8) {
                    nameBlock
                    ratingOnlyRow
                }
                .padding(10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondaryAppBackground)
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius))
            .cardShadow()
        }
        .buttonStyle(.plain)
        .disabled(model.isSubmitting)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Pick \(performer.displayName) as Gauntlet starter")
    }

    private var photoStack: some View {
        let r = cardCornerRadius
        return GeometryReader { geo in
            ZStack {
                Color.gray.opacity(DesignTokens.Opacity.placeholder)
                photoOverlay
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(HotOrNotPhotoTopClipShape(cornerRadius: r))
    }

    @ViewBuilder
    private var photoOverlay: some View {
        if let url = model.thumbnailURL(for: performer) {
            CustomAsyncImage(url: url) { loader in
                if loader.isLoading {
                    ProgressView()
                } else if let image = loader.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholderIcon
                }
            }
        } else {
            placeholderIcon
        }
    }

    private var placeholderIcon: some View {
        Image(systemName: "person.fill")
            .font(.largeTitle)
            .foregroundStyle(Color.appAccent.opacity(0.45))
    }

    private var nameBlock: some View {
        Text(performer.displayName)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.primary)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Same label/value typography as one cell in `HotOrNotBattleColumn`’s `detailGrid`, but only rating.
    private var ratingOnlyRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RATING")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Text(ratingText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HotOrNotFindResult: Codable {
    let count: Int
    let performers: [HotOrNotPerformerData]
}

private struct HotOrNotFindData: Codable {
    let findPerformers: HotOrNotFindResult
}

private struct HotOrNotFindResponse: Codable {
    let data: HotOrNotFindData?
}

private struct HotOrNotMutationData: Codable {
    let performerUpdate: HotOrNotUpdated?
}

private struct HotOrNotUpdated: Codable {
    let id: String
}

private struct HotOrNotMutationResponse: Codable {
    let data: HotOrNotMutationData?
}

/// Per-side duel outcome: `delta100` is the change in Stash `rating100` (same units as `outcomeSwiss` / server update); `rating100After` is the clamped new value.
private struct HotOrNotDuelVoteFeedback: Equatable {
    struct Side: Equatable {
        let delta100: Int
        let rating100After: Int
    }

    let left: Side
    let right: Side
}

// MARK: - ViewModel

@MainActor
private final class HotOrNotViewModel: ObservableObject {
    enum Section: String {
        case battle = "Duel"
        case leaderboard = "Charts"
    }

    /// Matches plugin `currentMode`: `"swiss" | "gauntlet" | "champion"` (persisted rawValue). UI order: Swiss → Champion → Gauntlet.
    enum DuelMode: String, CaseIterable, Identifiable {
        case swiss
        case champion
        case gauntlet

        var id: String { rawValue }

        var label: String {
            switch self {
            case .swiss: return "Swiss"
            case .champion: return "Champion"
            case .gauntlet: return "Gauntlet"
            }
        }
    }

    private static let duelModeDefaultsKey = "stashy.hotOrNot.duelMode"

    @Published var section: Section = .battle
    @Published var duelMode: DuelMode = .swiss {
        didSet { UserDefaults.standard.set(duelMode.rawValue, forKey: Self.duelModeDefaultsKey) }
    }
    @Published var selectedGenders: Set<String> = ["FEMALE"]
    @Published var left: HotOrNotPerformerData?
    @Published var right: HotOrNotPerformerData?
    @Published var rankLeft: Int?
    @Published var rankRight: Int?
    @Published var leaderboard: [HotOrNotPerformerData] = []
    @Published var isLoadingPair = false
    @Published var isSubmitting = false
    @Published var isLoadingBoard = false
    @Published var errorMessage: String?
    @Published var poolCount: Int = 0
    /// Shown on battle cards after a vote/draw; same `delta100` / `rating100After` as written via `performerUpdate`.
    @Published var duelFeedback: HotOrNotDuelVoteFeedback?

    // Climb state (plugin `gauntletChampion` / `gauntletWins` / `gauntletDefeated` / `gauntletFalling*`).
    @Published var climbChampion: HotOrNotPerformerData?
    @Published var climbWins: Int = 0
    @Published var climbDefeatedIds: Set<String> = []
    @Published var climbSkippedId: String?
    @Published var climbFalling: Bool = false
    @Published var climbFallingItem: HotOrNotPerformerData?
    @Published var climbVictory: HotOrNotPerformerData?
    @Published var gauntletStarters: [HotOrNotPerformerData] = []
    @Published var isLoadingGauntletStarters = false

    /// Inline Gauntlet starter grid (no sheet): need picks before the first duel.
    var needsGauntletStarterSelection: Bool {
        duelMode == .gauntlet && climbChampion == nil && !climbFalling && climbVictory == nil
    }

    private let client = GraphQLClient.shared
    private static let duelFeedbackDurationNs: UInt64 = 1_200_000_000
    /// `findPerformers` right after `performerUpdate` can still return old `rating100`; overlay last pushed values until reload finishes.
    private var pendingRating100ByPerformerId: [String: Int] = [:]

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.duelModeDefaultsKey),
           let m = DuelMode(rawValue: raw) {
            duelMode = m
        }
    }

    private var performerFilter: [String: Any] {
        let f: [String: Any] = [
            "gender": ["value_list": Array(selectedGenders).sorted(), "modifier": "INCLUDES"],
            "NOT": ["is_missing": "image"] as [String: Any]
        ]
        return f
    }

    func toggleGender(_ code: String) {
        if selectedGenders.contains(code) {
            if selectedGenders.count > 1 { selectedGenders.remove(code) }
        } else {
            selectedGenders.insert(code)
        }
    }

    func thumbnailURL(for p: HotOrNotPerformerData) -> URL? {
        if let path = p.image_path, path.hasPrefix("http://") || path.hasPrefix("https://") {
            return signedURL(URL(string: path))
        }
        guard let config = ServerConfigManager.shared.loadConfig(), config.hasValidConfig else { return nil }
        let s = "\(config.baseURL)/performer/\(p.id)/image"
        return signedURL(URL(string: s))
    }

    private func mergePendingRating(_ p: HotOrNotPerformerData) -> HotOrNotPerformerData {
        if let r = pendingRating100ByPerformerId[p.id] {
            return p.replacingRating100(r)
        }
        return p
    }

    func loadDuelPair() async {
        duelFeedback = nil
        if climbVictory != nil {
            left = nil
            right = nil
            rankLeft = nil
            rankRight = nil
            return
        }
        switch duelMode {
        case .swiss:
            await loadSwissPairContent()
        case .gauntlet:
            if climbChampion == nil && !climbFalling {
                isLoadingPair = false
                left = nil
                right = nil
                rankLeft = nil
                rankRight = nil
                await prepareGauntletStarters()
                return
            }
            await loadClimbPair(isGauntlet: true)
        case .champion:
            await loadClimbPair(isGauntlet: false)
        }
    }

    private func loadSwissPairContent() async {
        isLoadingPair = true
        errorMessage = nil
        defer { isLoadingPair = false }

        let query = GraphQLQueries.queryWithFragments("hotOrNotFindPerformers")
        let variables: [String: Any] = [
            "performer_filter": performerFilter,
            "filter": ["per_page": -1, "sort": "rating", "direction": "DESC"] as [String: Any]
        ]
        do {
            let res: HotOrNotFindResponse = try await client.execute(query: query, variables: variables)
            let list = res.data?.findPerformers.performers ?? []
            poolCount = res.data?.findPerformers.count ?? list.count
            guard list.count >= 2 else {
                errorMessage = "Not enough performers with images for the selected genders."
                left = nil
                right = nil
                rankLeft = nil
                rankRight = nil
                return
            }
            let weighted = list.enumerated().map { idx, p -> (Int, HotOrNotPerformerData, Double) in
                (idx, p, HotOrNotSwissMath.recencyWeight(stats: p.stats))
            }
            let w1 = weighted.map { $0.2 }
            guard let s1 = HotOrNotSwissMath.weightedPick(items: weighted, weights: w1) else { return }
            let rating1 = Double(s1.1.rating100 ?? 50)
            let similar = weighted.filter { $0.0 != s1.0 && abs(Double($0.1.rating100 ?? 50) - rating1) <= 15 }
            let s2: (Int, HotOrNotPerformerData, Double)
            if similar.isEmpty, let other = weighted.first(where: { $0.0 != s1.0 }) {
                s2 = other
            } else if let picked = HotOrNotSwissMath.weightedPick(items: similar, weights: similar.map { $0.2 }) {
                s2 = picked
            } else if let other = weighted.first(where: { $0.0 != s1.0 }) {
                s2 = other
            } else {
                return
            }
            left = mergePendingRating(s1.1)
            right = mergePendingRating(s2.1)
            rankLeft = s1.0 + 1
            rankRight = s2.0 + 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Champion / Gauntlet pairing (`handleMatchmakingLogic` in hot_or_not.js battle-engine).
    private func loadClimbPair(isGauntlet: Bool) async {
        isLoadingPair = true
        errorMessage = nil
        defer { isLoadingPair = false }

        let query = GraphQLQueries.queryWithFragments("hotOrNotFindPerformers")
        let variables: [String: Any] = [
            "performer_filter": performerFilter,
            "filter": ["per_page": -1, "sort": "rating", "direction": "DESC"] as [String: Any]
        ]
        do {
            let res: HotOrNotFindResponse = try await client.execute(query: query, variables: variables)
            let list = res.data?.findPerformers.performers ?? []
            poolCount = res.data?.findPerformers.count ?? list.count
            guard list.count >= 2 else {
                errorMessage = "Not enough performers with images for the selected genders."
                left = nil
                right = nil
                rankLeft = nil
                rankRight = nil
                return
            }

            if let cid = climbChampion?.id, let live = list.first(where: { $0.id == cid }) {
                climbChampion = mergePendingRating(live)
            }

            if isGauntlet, climbFalling, let fall = climbFallingItem {
                let candidates = list.filter {
                    $0.id != fall.id && !climbDefeatedIds.contains($0.id) && $0.id != climbSkippedId
                }
                if let opp = candidates.randomElement() {
                    left = mergePendingRating(fall)
                    right = mergePendingRating(opp)
                    rankLeft = list.firstIndex { $0.id == fall.id }.map { $0 + 1 }
                    rankRight = list.firstIndex { $0.id == opp.id }.map { $0 + 1 }
                } else if climbSkippedId != nil {
                    climbSkippedId = nil
                    await loadClimbPair(isGauntlet: true)
                    return
                } else {
                    let resolved = list.first(where: { $0.id == fall.id }).map { mergePendingRating($0) } ?? mergePendingRating(fall)
                    climbVictory = resolved
                    left = nil
                    right = nil
                    rankLeft = nil
                    rankRight = nil
                }
                climbSkippedId = nil
                return
            }

            if climbChampion == nil {
                let shuffled = list.shuffled()
                left = mergePendingRating(shuffled[0])
                right = mergePendingRating(shuffled[1])
                rankLeft = list.firstIndex { $0.id == shuffled[0].id }.map { $0 + 1 }
                rankRight = list.firstIndex { $0.id == shuffled[1].id }.map { $0 + 1 }
                climbSkippedId = nil
                return
            }

            guard let champ = climbChampion else { return }
            guard let champIdx = list.firstIndex(where: { $0.id == champ.id }) else {
                errorMessage = "Champion is no longer in this pool. Run reset."
                resetClimbStatePreservingMode()
                await loadDuelPair()
                return
            }

            let potential = list.enumerated()
                .filter { $0.offset < champIdx && !climbDefeatedIds.contains($0.element.id) && $0.element.id != climbSkippedId }
                .map { $0.element }

            if potential.isEmpty {
                if climbSkippedId != nil {
                    climbSkippedId = nil
                    await loadClimbPair(isGauntlet: isGauntlet)
                    return
                }
                climbVictory = mergePendingRating(list[champIdx])
                left = nil
                right = nil
                rankLeft = nil
                rankRight = nil
                return
            }

            let window = min(5, potential.count)
            let rIdx = Int.random(in: 0..<window)
            let opponent = potential[potential.count - 1 - rIdx]
            left = mergePendingRating(list[champIdx])
            right = mergePendingRating(opponent)
            rankLeft = champIdx + 1
            rankRight = (list.firstIndex { $0.id == opponent.id } ?? 0) + 1
            climbSkippedId = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetClimbStatePreservingMode() {
        climbChampion = nil
        climbWins = 0
        climbDefeatedIds = []
        climbSkippedId = nil
        climbVictory = nil
        climbFalling = false
        climbFallingItem = nil
        pendingRating100ByPerformerId.removeAll()
    }

    func startNewClimbRun() {
        resetClimbStatePreservingMode()
        Task { await loadDuelPair() }
    }

    func prepareGauntletStarters() async {
        isLoadingGauntletStarters = true
        errorMessage = nil
        defer { isLoadingGauntletStarters = false }
        let query = GraphQLQueries.queryWithFragments("hotOrNotFindPerformers")
        let variables: [String: Any] = [
            "performer_filter": performerFilter,
            "filter": ["per_page": 100, "sort": "random"] as [String: Any]
        ]
        do {
            let res: HotOrNotFindResponse = try await client.execute(query: query, variables: variables)
            let list = res.data?.findPerformers.performers ?? []
            gauntletStarters = Array(list.shuffled().prefix(4))
            if gauntletStarters.isEmpty {
                errorMessage = "No performers to pick as a Gauntlet starter."
            }
        } catch {
            errorMessage = error.localizedDescription
            gauntletStarters = []
        }
    }

    func pickGauntletStarter(_ p: HotOrNotPerformerData) {
        climbChampion = p
        climbWins = 0
        climbDefeatedIds = []
        climbFalling = false
        climbFallingItem = nil
        climbSkippedId = nil
        Task { await loadDuelPair() }
    }

    private func applyClimbAfterVote(winner: HotOrNotPerformerData, loser: HotOrNotPerformerData, newWinnerRating: Int, newLoserRating: Int) {
        switch duelMode {
        case .swiss:
            break
        case .champion:
            if climbChampion?.id == winner.id {
                climbDefeatedIds.insert(loser.id)
                climbWins += 1
                climbChampion = winner.replacingRating100(newWinnerRating)
            } else {
                climbChampion = winner.replacingRating100(newWinnerRating)
                climbWins = 1
            }
        case .gauntlet:
            if climbChampion?.id == winner.id {
                climbDefeatedIds.insert(loser.id)
                climbWins += 1
                climbChampion = winner.replacingRating100(newWinnerRating)
            } else if !climbFalling {
                climbFalling = true
                climbFallingItem = loser.replacingRating100(newLoserRating)
                climbDefeatedIds = [winner.id]
            } else {
                climbDefeatedIds.insert(winner.id)
            }
        }
    }

    func refreshLeaderboard() async {
        isLoadingBoard = true
        errorMessage = nil
        defer { isLoadingBoard = false }
        let query = GraphQLQueries.queryWithFragments("hotOrNotFindPerformers")
        let variables: [String: Any] = [
            "performer_filter": performerFilter,
            "filter": ["per_page": -1, "sort": "rating", "direction": "DESC"] as [String: Any]
        ]
        do {
            let res: HotOrNotFindResponse = try await client.execute(query: query, variables: variables)
            let list = res.data?.findPerformers.performers ?? []
            leaderboard = list.sorted { ($0.rating100 ?? 50) > ($1.rating100 ?? 50) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func choose(leftWins: Bool) async {
        guard let l = left, let r = right else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let winner = leftWins ? l : r
        let loser = leftWins ? r : l
        let wr = Double(winner.rating100 ?? 50)
        let lr = Double(loser.rating100 ?? 50)
        let loserRank = leftWins ? rankRight : rankLeft

        let champId = climbChampion?.id
        let fallId = climbFallingItem?.id
        let isChampionWinner = champId == winner.id
        let isChampionLoser = champId == loser.id
        let isFallingWinner = climbFalling && fallId == winner.id
        let isFallingLoser = climbFalling && fallId == loser.id

        let gain: Int
        let loss: Int
        switch duelMode {
        case .swiss:
            let o = HotOrNotSwissMath.outcomeSwiss(
                winnerRating: wr,
                loserRating: lr,
                winnerMatchCount: winner.stats.total_matches,
                loserMatchCount: loser.stats.total_matches
            )
            gain = o.winnerGain
            loss = o.loserLoss
        case .champion:
            let o = HotOrNotSwissMath.outcomeChampion(
                winnerRating: wr,
                loserRating: lr,
                winnerMatchCount: winner.stats.total_matches,
                loserMatchCount: loser.stats.total_matches
            )
            gain = o.winnerGain
            loss = o.loserLoss
        case .gauntlet:
            let o = HotOrNotSwissMath.outcomeGauntlet(
                winnerRating: wr,
                loserRating: lr,
                winnerMatchCount: winner.stats.total_matches,
                isChampionWinner: isChampionWinner,
                isFallingWinner: isFallingWinner,
                isChampionLoser: isChampionLoser,
                isFallingLoser: isFallingLoser,
                loserRank: loserRank
            )
            gain = o.winnerGain
            loss = o.loserLoss
        }
        let newW = min(100, max(1, (winner.rating100 ?? 50) + gain))
        let newL = min(100, max(1, (loser.rating100 ?? 50) - loss))
        let feedback: HotOrNotDuelVoteFeedback = if leftWins {
            HotOrNotDuelVoteFeedback(
                left: .init(delta100: gain, rating100After: newW),
                right: .init(delta100: -loss, rating100After: newL)
            )
        } else {
            HotOrNotDuelVoteFeedback(
                left: .init(delta100: -loss, rating100After: newL),
                right: .init(delta100: gain, rating100After: newW)
            )
        }
        do {
            try await pushPerformerUpdate(
                performer: winner,
                newRating: newW,
                won: true,
                opponentId: loser.id,
                opponentName: loser.name
            )
            try await pushPerformerUpdate(
                performer: loser,
                newRating: newL,
                won: false,
                opponentId: winner.id,
                opponentName: winner.name
            )
            pendingRating100ByPerformerId[winner.id] = newW
            pendingRating100ByPerformerId[loser.id] = newL
            applyClimbAfterVote(winner: winner, loser: loser, newWinnerRating: newW, newLoserRating: newL)
            HapticManager.light()
            withAnimation(.easeOut(duration: 0.18)) {
                duelFeedback = feedback
            }
            try await Task.sleep(nanoseconds: Self.duelFeedbackDurationNs)
            withAnimation(.easeOut(duration: 0.15)) {
                duelFeedback = nil
            }
            await loadDuelPair()
            pendingRating100ByPerformerId.removeValue(forKey: winner.id)
            pendingRating100ByPerformerId.removeValue(forKey: loser.id)
            if section == .leaderboard { await refreshLeaderboard() }
        } catch {
            pendingRating100ByPerformerId.removeValue(forKey: winner.id)
            pendingRating100ByPerformerId.removeValue(forKey: loser.id)
            errorMessage = error.localizedDescription
        }
    }

    func skipDraw() async {
        guard duelMode != .champion else { return }
        guard let l = left, let r = right else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let lr = Double(l.rating100 ?? 50)
        let rr = Double(r.rating100 ?? 50)
        let (lg, rrLoss) = HotOrNotSwissMath.outcomeDraw(
            leftRating: lr,
            rightRating: rr,
            leftMatches: l.stats.total_matches,
            rightMatches: r.stats.total_matches
        )
        let newL = min(100, max(1, (l.rating100 ?? 50) + lg))
        let newR = min(100, max(1, (r.rating100 ?? 50) - rrLoss))
        let feedback = HotOrNotDuelVoteFeedback(
            left: .init(delta100: lg, rating100After: newL),
            right: .init(delta100: -rrLoss, rating100After: newR)
        )
        if duelMode == .gauntlet {
            climbSkippedId = r.id
        }
        do {
            try await pushPerformerUpdate(performer: l, newRating: newL, won: nil, opponentId: r.id, opponentName: r.name)
            try await pushPerformerUpdate(performer: r, newRating: newR, won: nil, opponentId: l.id, opponentName: l.name)
            pendingRating100ByPerformerId[l.id] = newL
            pendingRating100ByPerformerId[r.id] = newR
            HapticManager.light()
            withAnimation(.easeOut(duration: 0.18)) {
                duelFeedback = feedback
            }
            try await Task.sleep(nanoseconds: Self.duelFeedbackDurationNs)
            withAnimation(.easeOut(duration: 0.15)) {
                duelFeedback = nil
            }
            await loadDuelPair()
            pendingRating100ByPerformerId.removeValue(forKey: l.id)
            pendingRating100ByPerformerId.removeValue(forKey: r.id)
            if section == .leaderboard { await refreshLeaderboard() }
        } catch {
            pendingRating100ByPerformerId.removeValue(forKey: l.id)
            pendingRating100ByPerformerId.removeValue(forKey: r.id)
            errorMessage = error.localizedDescription
        }
    }

    private func pushPerformerUpdate(
        performer: HotOrNotPerformerData,
        newRating: Int,
        won: Bool?,
        opponentId: String,
        opponentName: String
    ) async throws {
        let stats = HotOrNotSwissMath.updateStats(performer.stats, won: won)
        let statsJson = try HotOrNotSwissMath.encodeStats(stats)
        var records = HotOrNotSwissMath.parseMatchRecords(from: performer.custom_fields)
        let opponentField = "\(opponentId):\(opponentName)"
        records.append(HotOrNotMatchRecord(
            date: ISO8601DateFormatter().string(from: Date()),
            opponent: opponentField,
            won: won,
            ratingAfter: newRating
        ))
        if records.count > 30 { records = Array(records.suffix(30)) }
        let recordJson = try HotOrNotSwissMath.encodeMatchRecords(records)

        let partial: [String: Any] = [
            "hotornot_stats": statsJson,
            "performer_record": recordJson
        ]
        let input: [String: Any] = [
            "id": performer.id,
            "rating100": newRating,
            "custom_fields": ["partial": partial] as [String: Any]
        ]
        let mutation = """
        mutation HotOrNotPerformerUpdate($input: PerformerUpdateInput!) {
          performerUpdate(input: $input) { id rating100 }
        }
        """
        let res: HotOrNotMutationResponse = try await client.execute(
            query: mutation,
            variables: ["input": input]
        )
        if res.data?.performerUpdate == nil {
            throw NSError(domain: "HotOrNot", code: 1, userInfo: [NSLocalizedDescriptionKey: "Update failed"])
        }
    }
}

// MARK: - UI

struct HotOrNotToolsView: View {
    /// Matches main scroll content in `PerformerDetailView` (e.g. header + lists).
    private static let contentHorizontalPadding: CGFloat = 16

    @StateObject private var model = HotOrNotViewModel()
    @ObservedObject private var appearance = AppearanceManager.shared
    @State private var showPoolSettings = false
    /// Avoids re-running `loadDuelPair` when returning from `NavigationLink` (e.g. Profile): `.task` restarts after disappear/reappear.
    @State private var didRunInitialHotOrNotLoad = false

    var body: some View {
        VStack(spacing: 0) {
            if let err = model.errorMessage {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Self.contentHorizontalPadding)
            }

            switch model.section {
            case .battle:
                battleContent
            case .leaderboard:
                leaderboardContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if shouldShowDuelActionsAboveFloatingBar {
                    hotOrNotDuelActionsRow
                        .padding(.horizontal, Self.contentHorizontalPadding)
                }
                hotOrNotBottomChrome
            }
        }
        .sheet(isPresented: $showPoolSettings) {
            HotOrNotPoolSettingsSheet(viewModel: model)
        }
        .onAppear {
            guard !didRunInitialHotOrNotLoad else { return }
            didRunInitialHotOrNotLoad = true
            Task {
                await model.loadDuelPair()
                await model.refreshLeaderboard()
            }
        }
        .onChange(of: model.selectedGenders) { _, _ in
            Task {
                await model.loadDuelPair()
                await model.refreshLeaderboard()
            }
        }
        .onChange(of: model.duelMode) { _, _ in
            model.resetClimbStatePreservingMode()
            Task { await model.loadDuelPair() }
        }
        .onChange(of: model.section) { _, newSection in
            HapticManager.selection()
            if newSection == .leaderboard {
                Task { await model.refreshLeaderboard() }
            }
        }
    }

    /// Gleiche Logik wie der Zweig in `battleContent` mit Karten + Aktionen (kein Sieger-/Gauntlet-Start-UI).
    private var shouldShowDuelActionsAboveFloatingBar: Bool {
        guard model.section == .battle else { return false }
        guard model.climbVictory == nil else { return false }
        guard !model.needsGauntletStarterSelection else { return false }
        if model.isLoadingPair && model.left == nil { return false }
        return model.left != nil && model.right != nil
    }

    /// Zeile mit Draw, New pair, Stop — direkt über dem unteren Modus/Charts-Chrome (Scroll-Bereich bleibt frei).
    @ViewBuilder
    private var hotOrNotDuelActionsRow: some View {
        HStack(spacing: 10) {
            if model.duelMode == .champion {
                Button {
                    HapticManager.light()
                    model.startNewClimbRun()
                } label: {
                    Label("Stop", systemImage: "stop.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.isSubmitting)
                .accessibilityLabel("End Champion run")
            } else {
                Button {
                    Task { await model.skipDraw() }
                } label: {
                    Label("Draw", systemImage: "equal.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.isSubmitting)
            }

            if model.duelMode == .gauntlet {
                Button(action: {}) {
                    Label("New pair", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(true)
                .accessibilityLabel("New pair, not available in Gauntlet")

                Button {
                    HapticManager.light()
                    model.startNewClimbRun()
                } label: {
                    Label("Stop", systemImage: "stop.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(appearance.tintColor)
                .disabled(model.isSubmitting)
                .accessibilityLabel("End Gauntlet run")
            } else {
                Button {
                    Task { await model.loadDuelPair() }
                } label: {
                    Label("New pair", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(appearance.tintColor)
                .disabled(model.isSubmitting || model.isLoadingPair)
            }
        }
    }

    /// Single bottom chrome: duel modes + Charts + pool (replaces separate mode picker + old segmented Duel/Charts bar).
    private var hotOrNotBottomChrome: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                hotOrNotDuelModeChip(.swiss)
                hotOrNotDuelModeChip(.champion)
                hotOrNotDuelModeChip(.gauntlet)
            }
            HStack(spacing: 10) {
                hotOrNotChartsChip
                    .frame(maxWidth: .infinity)
                Button {
                    HapticManager.light()
                    showPoolSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pool settings")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private func hotOrNotDuelModeChip(_ mode: HotOrNotViewModel.DuelMode) -> some View {
        let selected = model.section == .battle && model.duelMode == mode
        return Button {
            HapticManager.selection()
            model.section = .battle
            if model.duelMode != mode {
                model.duelMode = mode
            }
        } label: {
            Text(mode.label)
                .font(.system(size: 12, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? appearance.tintColor.opacity(0.32) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(selected ? 0.0 : 0.1), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(model.isSubmitting)
        .accessibilityLabel("\(mode.label) mode\(selected ? ", selected" : "")")
    }

    private var hotOrNotChartsChip: some View {
        let selected = model.section == .leaderboard
        return Button {
            HapticManager.selection()
            model.section = .leaderboard
        } label: {
            Text("Charts")
                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? appearance.tintColor.opacity(0.32) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(selected ? 0.0 : 0.1), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Charts\(selected ? ", selected" : "")")
    }

    @ViewBuilder
    private var gauntletStarterInline: some View {
        VStack(spacing: 10) {
            if model.isLoadingGauntletStarters && model.gauntletStarters.isEmpty {
                ProgressView()
                    .padding(.vertical, 28)
            } else if model.gauntletStarters.isEmpty {
                ContentUnavailableView(
                    "No starters",
                    systemImage: "person.2.slash",
                    description: Text(model.errorMessage ?? "")
                )
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 12
                ) {
                    ForEach(Array(model.gauntletStarters.prefix(4)), id: \.id) { p in
                        HotOrNotGauntletStarterPickCard(
                            model: model,
                            performer: p,
                            onPick: { model.pickGauntletStarter(p) }
                        )
                    }
                }
            }
        }
    }

    private var battleContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let victor = model.climbVictory {
                    VStack(spacing: 12) {
                        Text("Champion!")
                            .font(.title2.weight(.bold))
                        Text(victor.displayName)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        Text("\(model.climbWins) wins · cleared the ladder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            model.startNewClimbRun()
                        } label: {
                            Text("New run")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(appearance.tintColor)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .background(Color.secondaryAppBackground)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
                    .cardShadow()
                } else if model.needsGauntletStarterSelection {
                    gauntletStarterInline
                } else if model.isLoadingPair && model.left == nil {
                    ProgressView("Loading pair…")
                        .padding(.top, 40)
                } else if let l = model.left, let r = model.right {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(spacing: 10) {
                            HotOrNotProfileLinkCard(performer: l)
                            HotOrNotBattleColumn(
                                model: model,
                                performer: l,
                                rank: model.rankLeft,
                                voteFeedback: model.duelFeedback?.left,
                                choose: { Task { await model.choose(leftWins: true) } }
                            )
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: 10) {
                            HotOrNotProfileLinkCard(performer: r)
                            HotOrNotBattleColumn(
                                model: model,
                                performer: r,
                                rank: model.rankRight,
                                voteFeedback: model.duelFeedback?.right,
                                choose: { Task { await model.choose(leftWins: false) } }
                            )
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, Self.contentHorizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private var leaderboardContent: some View {
        Group {
            if model.isLoadingBoard && model.leaderboard.isEmpty {
                ProgressView("Loading charts…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(model.leaderboard.enumerated()), id: \.element.id) { index, p in
                            NavigationLink {
                                PerformerDetailView(performer: p.toPerformerStub())
                            } label: {
                                HotOrNotLeaderboardCard(model: model, performer: p, place: index + 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Self.contentHorizontalPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }
            }
        }
    }
}

// MARK: - Leaderboard card

private struct HotOrNotLeaderboardCard: View {
    @ObservedObject var model: HotOrNotViewModel
    let performer: HotOrNotPerformerData
    let place: Int

    private static let thumbWidth: CGFloat = 68
    private static let thumbHeight: CGFloat = 90

    private var s: HotOrNotStats { performer.stats }

    private var ratingDisplay: String {
        "\(performer.rating100 ?? 50)"
    }

    private var streakSummaryLine: String? {
        let parts: [String] = [
            s.current_streak != 0 ? "Current \(streakSigned(s.current_streak))" : nil,
            s.best_streak > 0 ? "Best +\(s.best_streak)" : nil,
            s.worst_streak < 0 ? "Worst \(s.worst_streak)" : nil
        ].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private func streakSigned(_ n: Int) -> String {
        n > 0 ? "+\(n)" : "\(n)"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            thumbnailWithRank
            VStack(alignment: .leading, spacing: 6) {
                Text(performer.displayName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                hotOrNotStatsBlock
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .cardShadow()
    }

    private var thumbnailWithRank: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                .fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                .frame(width: Self.thumbWidth, height: Self.thumbHeight)
                .overlay(photoOverlay)
                .clipped()

            Text("#\(place)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(4)
        }
    }

    private var hotOrNotStatsBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 4) {
                leaderboardStatColumn(title: "Rating", value: ratingDisplay)
                leaderboardStatColumn(title: "Duels", value: "\(s.total_matches)")
                leaderboardStatColumn(title: "W", value: "\(s.wins)")
                leaderboardStatColumn(title: "L", value: "\(s.losses)")
                leaderboardStatColumn(title: "D", value: "\(s.draws)")
            }

            if let streak = streakSummaryLine {
                Text(streak)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func leaderboardStatColumn(title: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 1) {
            Text(title)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)
            Text(value)
                .font(.title2.monospacedDigit().weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var photoOverlay: some View {
        Group {
            if let url = model.thumbnailURL(for: performer) {
                CustomAsyncImage(url: url) { loader in
                    if loader.isLoading {
                        ProgressView()
                            .scaleEffect(0.85)
                    } else if let image = loader.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholderIcon
                    }
                }
            } else {
                placeholderIcon
            }
        }
        .frame(width: Self.thumbWidth, height: Self.thumbHeight)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
    }

    private var placeholderIcon: some View {
        Image(systemName: "person.fill")
            .font(.title2)
            .foregroundStyle(Color.appAccent.opacity(0.45))
    }
}

// MARK: - Pool settings (genders sheet)

private struct HotOrNotPoolSettingsSheet: View {
    @ObservedObject var viewModel: HotOrNotViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appearance = AppearanceManager.shared

    private static let genderRows: [(code: String, label: String)] = [
        ("FEMALE", "Female"),
        ("MALE", "Male"),
        ("TRANSGENDER_FEMALE", "Transgender (female)"),
        ("TRANSGENDER_MALE", "Transgender (male)"),
        ("NON_BINARY", "Non-binary"),
        ("INTERSEX", "Intersex")
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Genders in pool") {
                    ForEach(Self.genderRows, id: \.code) { row in
                        Toggle(isOn: genderBinding(code: row.code)) {
                            Text(row.label)
                        }
                        .tint(appearance.tintColor)
                        .listRowBackground(Color.secondaryAppBackground)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Pool settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .applyAppBackground()
    }

    private func genderBinding(code: String) -> Binding<Bool> {
        Binding(
            get: { viewModel.selectedGenders.contains(code) },
            set: { newValue in
                let was = viewModel.selectedGenders.contains(code)
                guard newValue != was else { return }
                viewModel.toggleGender(code)
            }
        )
    }
}

#endif
