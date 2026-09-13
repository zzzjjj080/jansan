import SwiftUI
import JansanCore

/// 1人ぶんの詳しい成績と、相手ごとの相性。集計の表で名前をタップすると開く。
///
/// **集計画面と同じ対局を受け取る**（期間・打ち方・表示モードで絞ったもの）。
/// ここで絞り直すと、表の数字と詳細の数字が食い違う。
struct PlayerStatsView: View {
    let name: String
    let games: [GameForStats]
    let decimalMode: Bool
    /// 三麻なら3、四麻なら4。着順の棒をいくつ並べるか
    let seats: Int
    let color: Color

    var body: some View {
        let report = Report.players(games: games).first { $0.name == name }
        let matchups = Report.matchups(for: name, games: games)
        List {
            if let report {
                overview(report)
                rankSection(report)
                scoreSection(report)
                streakSection(report)
                gameSection(report)
                if let recent = report.recent, report.rounds > Report.recentRounds {
                    recentSection(report, recent)
                }
                matchupSection(matchups)
            } else {
                ContentUnavailableView("この条件では打っていません",
                                       systemImage: "person.crop.circle.badge.questionmark")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 概要

    private func overview(_ r: PlayerReport) -> some View {
        Section {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle().fill(color).frame(width: 9, height: 9)
                        Text(name).font(.headline)
                    }
                    Text("\(r.games)対局・\(r.rounds)局")
                        .font(.caption)
                        .foregroundStyle(Palette.inkDim)
                }
                Spacer()
                Text(StatsFormat.signed(r.total, decimalMode))
                    .font(.system(size: 28, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(r.total < 0 ? Palette.negative : Palette.ink)
            }
            .accessibilityElement(children: .combine)

            item("1局の平均", StatsFormat.average(r.averageScore, decimalMode),
                 negative: (r.averageScore ?? 0) < 0)
        }
    }

    // MARK: - 着順

    private func rankSection(_ r: PlayerReport) -> some View {
        Section {
            ForEach(1...max(seats, r.rankCounts.count), id: \.self) { rank in
                rankBar(rank: rank, count: r.count(ofRank: rank), rounds: r.rounds)
            }
            item("平均着順", StatsFormat.rank(r.averageRank))
            item("トップ率", StatsFormat.percent(r.topRate))
            item("連対率（1〜2位）", StatsFormat.percent(r.rentaiRate))
            item("ラス率", StatsFormat.percent(r.lastRate))
            item("ラス回避率", StatsFormat.percent(r.lastAvoidRate))
        } header: {
            Text("着順")
        } footer: {
            Text("・平均着順は小さいほど良い成績です\n・ラスはその局の最下位です（三麻なら3位、四麻なら4位）")
        }
    }

    private func rankBar(rank: Int, count: Int, rounds: Int) -> some View {
        let share = rounds > 0 ? Double(count) / Double(rounds) : 0
        return HStack(spacing: 10) {
            Text("\(rank)位")
                .font(.system(size: 13, weight: .bold))
                .frame(width: 30, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.surface2)
                    Capsule()
                        .fill(StatsFormat.rankColor(rank, seats: seats))
                        .frame(width: count > 0 ? max(6, geo.size.width * share) : 0)
                }
            }
            .frame(height: 10)
            Text("\(count)回")
                .font(.system(size: 12))
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
            Text(StatsFormat.percent(share))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rank)位 \(count)回 \(StatsFormat.percent(share))")
    }

    // MARK: - 1局の点数

    private func scoreSection(_ r: PlayerReport) -> some View {
        Section {
            item("プラスで終えた局", StatsFormat.percent(r.plusRate))
            item("最高", r.bestRound.map { StatsFormat.signed($0, decimalMode) } ?? "–")
            item("最低", r.worstRound.map { StatsFormat.signed($0, decimalMode) } ?? "–",
                 negative: (r.worstRound ?? 0) < 0)
            item("ばらつき", StatsFormat.spread(r.spread, decimalMode))
        } header: {
            Text("1局の点数")
        } footer: {
            Text("・ばらつきは1局の点数の標準偏差です\n・小さいほど大勝ちも大負けも少なく、安定しています")
        }
    }

    // MARK: - 連続記録

    private func streakSection(_ r: PlayerReport) -> some View {
        Section {
            item("連続トップ", "\(r.longestTopStreak)局")
            item("連続ラス", "\(r.longestLastStreak)局")
            item("ラスを引かない連続", "\(r.longestNoLastStreak)局")
        } header: {
            Text("連続記録（最長）")
        } footer: {
            Text("対局日の順に並べて数えています。")
        }
    }

    // MARK: - 対局ごと

    private func gameSection(_ r: PlayerReport) -> some View {
        Section {
            item("対局のトップ", "\(r.gameTops)回（\(StatsFormat.percent(r.gameTopRate))）")
            item("プラスで終えた対局", "\(r.plusGames)回（\(StatsFormat.percent(r.gamePlusRate))）")
            item("最高の対局", r.bestGame.map { StatsFormat.signed($0, decimalMode) } ?? "–")
            item("最低の対局", r.worstGame.map { StatsFormat.signed($0, decimalMode) } ?? "–",
                 negative: (r.worstGame ?? 0) < 0)
        } header: {
            Text("対局ごと")
        } footer: {
            Text("保存した1回ぶんの表の合計で見た成績です。")
        }
    }

    // MARK: - 最近の調子

    private func recentSection(_ r: PlayerReport, _ recent: PlayerReport.RecentForm) -> some View {
        let overall = r.averageRank ?? recent.averageRank
        let delta = recent.averageRank - overall
        let (trend, trendColor): (String, Color) =
            delta < -0.05 ? ("上向き", Palette.accent)
            : delta > 0.05 ? ("下向き", Palette.negative)
            : ("いつも通り", Palette.inkDim)
        return Section {
            LabeledContent("直近\(recent.rounds)局の平均着順") {
                HStack(spacing: 6) {
                    Text(StatsFormat.rank(recent.averageRank)).monospacedDigit()
                    Text(trend)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(trendColor)
                }
            }
            item("直近\(recent.rounds)局の収支", StatsFormat.signed(recent.total, decimalMode),
                 negative: recent.total < 0)
        } header: {
            Text("最近の調子")
        } footer: {
            Text("・全体の平均着順（\(StatsFormat.rank(overall))）と比べています\n・平均着順が全体より小さければ上向きです")
        }
    }

    // MARK: - 相性

    private func matchupSection(_ matchups: [Matchup]) -> some View {
        Section {
            if matchups.isEmpty {
                Text("一緒に打った人がいません")
                    .foregroundStyle(Palette.inkDim)
            }
            ForEach(matchups) { m in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.opponent).font(.system(size: 14, weight: .bold))
                        Text("\(m.rounds)局 一緒に打った")
                            .font(.caption)
                            .foregroundStyle(Palette.inkDim)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("上回った \(StatsFormat.percent(m.winRate))")
                            .font(.system(size: 13, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(m.winRate >= 0.5 ? Palette.accent : Palette.negative)
                        Text("平均差 \(StatsFormat.average(m.averageDifference, decimalMode))")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Palette.inkDim)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("相性")
        } footer: {
            Text("・同じ局を打った相手ごとの成績です\n・「上回った」はその局の着順が相手より上だった割合です\n・「平均差」は1局あたりの点数の差です")
        }
    }

    private func item(_ title: String, _ value: String, negative: Bool = false) -> some View {
        LabeledContent(title) {
            Text(value)
                .monospacedDigit()
                .foregroundStyle(negative ? Palette.negative : Palette.ink)
        }
    }
}

/// 集計の数字の書き方。集計画面と詳細で同じ書き方にする
enum StatsFormat {
    static func percent(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(Int((value * 100).rounded()))%"
    }

    static func score(_ value: Int, _ decimalMode: Bool) -> String {
        ScoreFormatter.string(value, decimalMode: decimalMode)
    }

    static func signed(_ value: Int, _ decimalMode: Bool) -> String {
        ScoreFormatter.signedString(value, decimalMode: decimalMode)
    }

    /// 平均の点数。保持している整数の単位で丸めてから、表示モードで書く
    static func average(_ value: Double?, _ decimalMode: Bool) -> String {
        guard let value else { return "–" }
        return ScoreFormatter.signedString(Int(value.rounded()), decimalMode: decimalMode)
    }

    static func rank(_ value: Double?) -> String {
        value.map { String(format: "%.2f", $0) } ?? "–"
    }

    static func spread(_ value: Double?, _ decimalMode: Bool) -> String {
        guard let value else { return "–" }
        return "±" + ScoreFormatter.string(Int(value.rounded()), decimalMode: decimalMode)
    }

    static func styleLabel(_ style: Int?) -> String {
        switch style {
        case 3: "三麻"
        case 4: "四麻"
        default: "三麻と四麻"
        }
    }

    /// 1位は緑、最下位は赤、あいだは落ち着いた色
    static func rankColor(_ rank: Int, seats: Int) -> Color {
        if rank == 1 { return Palette.accent }
        if rank >= seats { return Palette.negative }
        return rank == 2 ? Palette.toneBInk : Palette.inkDim
    }
}
