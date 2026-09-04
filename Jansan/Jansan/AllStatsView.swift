import SwiftUI
import SwiftData
import Charts
import JansanCore

/// 保存した記録をまたいだ集計。
///
/// 1つの表の中を見る `StatsView` とは別物。
/// **人数を必ず選ばせる。** 3人局と4人局を混ぜると着順率の分母が変わり、
/// 数字の意味が壊れる。表示モードも同じ理由で分ける（混ぜると10倍ズレる）。
struct AllStatsView: View {
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<SavedGame> { !$0.isDraft }, sort: \SavedGame.savedAt, order: .reverse)
    private var records: [SavedGame]

    @State private var period: Period = .all
    @State private var playerCount: Int?
    @State private var decimalMode: Bool?
    @State private var soloed: String?

    /// 画面に出す期間の選択肢。Core の StatsPeriod は custom を持つが、
    /// ここでは日付の入力欄を作らず、よく使う範囲だけに絞る
    private enum Period: String, CaseIterable, Identifiable {
        case all, thisMonth, lastMonth, last30, thisYear
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: "全期間"
            case .thisMonth: "今月"
            case .lastMonth: "先月"
            case .last30: "30日"
            case .thisYear: "今年"
            }
        }
        var core: StatsPeriod {
            switch self {
            case .all: .all
            case .thisMonth: .thisMonth
            case .lastMonth: .lastMonth
            case .last30: .last30Days
            case .thisYear: .thisYear
            }
        }
    }

    // MARK: - 集計の材料

    private var games: [GameForStats] {
        records.compactMap { record in
            guard let snapshot = try? record.snapshot() else { return nil }
            return GameForStats(playedAt: record.effectivePlayedAt, session: snapshot.session)
        }
    }

    private var availableCounts: [Int] { Aggregator.availablePlayerCounts(games: games) }

    /// 記録の中に小数モードと整数モードが混ざっているときだけ、切り替えを出す
    private var hasMixedDecimalModes: Bool {
        Set(games.map(\.session.decimalMode)).count > 1
    }

    private var selected: [GameForStats] {
        Aggregator.filter(games: games, period: period.core,
                          playerCount: playerCount, decimalMode: decimalMode)
    }

    private var stats: [AggregatedStats] {
        Aggregator.aggregate(games: games, period: period.core,
                             playerCount: playerCount, decimalMode: decimalMode)
    }

    /// 表示に使うモード。絞っていないときは多数派に合わせる
    private var displayDecimalMode: Bool {
        decimalMode ?? (selected.filter(\.session.decimalMode).count * 2 > selected.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    filters
                    if records.isEmpty {
                        ContentUnavailableView(
                            "まだ記録がありません",
                            systemImage: "tray",
                            description: Text("設定の「この対局を記録に残す」で保存すると、ここでまとめて集計できます。")
                        )
                        .padding(.top, 30)
                    } else if stats.isEmpty {
                        ContentUnavailableView(
                            "この条件に合う対局がありません",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("期間や人数を変えてみてください。")
                        )
                        .padding(.top, 30)
                    } else {
                        summary
                        heading("成績")
                        ScrollView(.horizontal, showsIndicators: false) { table }
                        heading("推移（対局ごとの累計）")
                        chart
                        legend
                    }
                }
                .padding(16)
            }
            .background(Palette.bg)
            .navigationTitle("全記録のビュー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .onAppear {
            // いちばん多く打っている人数を最初に選んでおく。混ざった数字を最初に見せない
            if playerCount == nil {
                let counts = games.map(\.playerCount)
                playerCount = counts.mostCommon() ?? availableCounts.last
            }
        }
    }

    // MARK: - 絞り込み

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("期間", selection: $period) {
                ForEach(Period.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("periodPicker")

            if availableCounts.count > 1 {
                Picker("人数", selection: $playerCount) {
                    ForEach(availableCounts, id: \.self) { count in
                        Text("\(count)人打ち").tag(Int?.some(count))
                    }
                    Text("すべて").tag(Int?.none)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("playerCountPicker")
            }

            if hasMixedDecimalModes {
                Picker("表示モード", selection: $decimalMode) {
                    Text("整数").tag(Bool?.some(false))
                    Text("小数").tag(Bool?.some(true))
                    Text("すべて").tag(Bool?.none)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("decimalModePicker")
            }

            if playerCount == nil && availableCounts.count > 1 {
                warning("人数の違う対局が混ざっています。着順の分母が変わるため、着順率と平均着順は比べられません。")
            }
            if decimalMode == nil && hasMixedDecimalModes {
                warning("小数モードの記録と整数モードの記録が混ざっています。合計が10倍ズレて見えます。")
            }
        }
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 11))
            .foregroundStyle(Palette.negative)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var summary: some View {
        Text("\(selected.count) 対局 ・ \(stats.map(\.played).max() ?? 0) 局")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Palette.accent)
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .kerning(0.5)
            .foregroundStyle(Palette.inkDim)
    }

    // MARK: - 成績表

    private var rankColumns: [Int] {
        let highest = stats.flatMap { $0.rankCounts.keys }.max() ?? 0
        return Array(1...max(playerCount ?? 4, highest))
    }

    private var table: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                Text("").gridColumnAlignment(.leading)
                headerCell("対局")
                headerCell("合計")
                headerCell("平均")
                ForEach(rankColumns, id: \.self) { headerCell("\($0)位") }
                headerCell("平着")
                headerCell("トップ")
                headerCell("ラス")
            }
            .padding(.bottom, 6)

            ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                GridRow {
                    Text(stat.name)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .gridColumnAlignment(.leading)
                        .padding(.trailing, 10)

                    numberCell("\(stat.games)")
                    numberCell(ScoreFormatter.string(stat.total, decimalMode: displayDecimalMode),
                               negative: stat.total < 0)
                    numberCell(stat.averageScore.map {
                        ScoreFormatter.string(Int($0.rounded()), decimalMode: displayDecimalMode)
                    } ?? "–", negative: (stat.averageScore ?? 0) < 0)

                    ForEach(rankColumns, id: \.self) { rank in
                        Text("\(stat.count(ofRank: rank))")
                            .font(.system(size: 12.5, weight: stat.count(ofRank: rank) > 0 ? .bold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(heatColor(stat.count(ofRank: rank)),
                                        in: RoundedRectangle(cornerRadius: 6))
                    }

                    numberCell(stat.averageRank.map { String(format: "%.2f", $0) } ?? "–")
                    numberCell(percent(stat.topRate))
                    numberCell(percent(stat.lastRate))
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func headerCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Palette.inkDim)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
    }

    private func numberCell(_ text: String, negative: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 12.5, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(negative ? Palette.negative : Palette.ink)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(Int((value * 100).rounded()))%"
    }

    private var heatMax: Int {
        max(1, stats.flatMap { s in rankColumns.map { s.count(ofRank: $0) } }.max() ?? 1)
    }

    private func heatColor(_ count: Int) -> Color {
        guard count > 0 else { return Palette.inkDim.opacity(0.10) }
        let t = Double(count) / Double(heatMax)
        let base = t <= 0.5
            ? Palette.inkDim.mix(with: Palette.toneBInk, by: t / 0.5)
            : Palette.toneBInk.mix(with: Palette.negative, by: (t - 0.5) / 0.5)
        return base.opacity(0.20 + t * 0.45)
    }

    // MARK: - 推移

    private struct Series: Identifiable {
        let id: String
        let color: Color
        let points: [Int]

        struct Point: Identifiable {
            let index: Int
            let value: Int
            var id: Int { index }
        }

        /// 先頭に0を足して原点から引く。足さないとグラフの左半分が空いて、
        /// どこが始まりなのか読めない
        var plotted: [Point] {
            ([0] + points).enumerated().map { Point(index: $0.offset, value: $0.element) }
        }
    }

    private var series: [Series] {
        Aggregator.cumulative(games: games, period: period.core,
                              playerCount: playerCount, decimalMode: decimalMode)
            .enumerated()
            .map { index, item in
                Series(id: item.name,
                       color: Palette.playerColors[index % Palette.playerColors.count],
                       points: item.values)
            }
    }

    /// 目盛りの位置。対局数は整数なので、小数のラベルが出ないよう自分で並べる
    private var xTicks: [Int] {
        let count = series.first?.points.count ?? 0
        guard count > 0 else { return [0] }
        let step = Swift.max(1, count / 5)
        return Array(stride(from: step, through: count, by: step))
    }

    private var chart: some View {
        Chart {
            ForEach(series) { line in
                ForEach(line.plotted) { point in
                    LineMark(
                        x: .value("対局", point.index),
                        y: .value("累計", point.value)
                    )
                    .foregroundStyle(line.color)
                    .opacity(opacity(for: line.id))
                }
            }
        }
        .chartLegend(.hidden)
        .chartXAxis {
            // 対局数は整数。目盛りの位置を自分で並べて、小数のラベルを出さない
            AxisMarks(values: xTicks) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let n = value.as(Int.self) { Text("\(n)") }
                }
            }
        }
        .frame(height: 220)
    }

    private var legend: some View {
        // 凡例をタップすると1人だけ強調する。既存のビューと同じ操作にしてある
        FlowRow(spacing: 8) {
            ForEach(series) { line in
                Button {
                    soloed = soloed == line.id ? nil : line.id
                } label: {
                    HStack(spacing: 5) {
                        Circle().fill(line.color).frame(width: 8, height: 8)
                        Text(line.id).font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Palette.surface2, in: Capsule())
                    .opacity(opacity(for: line.id))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .sensoryFeedback(.selection, trigger: soloed)
    }

    private func opacity(for name: String) -> Double {
        guard let soloed else { return 1 }
        return soloed == name ? 1 : 0.18
    }
}

/// 凡例を折り返して並べる。人数が増えても画面からはみ出さない
private struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private extension Array where Element: Hashable {
    /// いちばん多く出てくる値
    func mostCommon() -> Element? {
        Dictionary(grouping: self, by: { $0 }).max { $0.value.count < $1.value.count }?.key
    }
}
