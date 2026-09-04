import SwiftUI
import Charts
import JansanCore

struct StatsView: View {
    let board: ScoreBoard
    @Environment(\.dismiss) private var dismiss

    /// 凡例をタップして1人だけ強調している状態
    @State private var soloed: String?
    @State private var showAll = false

    private var session: Session { board.session }
    private var stats: [PlayerStats] { session.playerStats() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if stats.allSatisfy({ $0.played == 0 }) {
                        ContentUnavailableView(
                            "まだ集計できる局がありません",
                            systemImage: "chart.line.uptrend.xyaxis",
                            description: Text("全員の点数が入った局が1つ以上あると、着順と推移が出ます。")
                        )
                        .padding(.top, 40)

                        // この対局に集計できる局が無くても、過去の記録は見たい
                        Button("保存した記録をまとめて見る") { showAll = true }
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    } else {
                        heading("着順・成績")
                        ScrollView(.horizontal, showsIndicators: false) {
                            rankTable
                        }
                        heading("推移（累計点数）")
                        trendChart
                        legend
                    }
                }
                .padding(16)
            }
            .background(Palette.bg)
            .navigationTitle("ビュー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        showAll = true
                    } label: {
                        Label("全記録", systemImage: "square.stack.3d.up")
                    }
                    .accessibilityIdentifier("showAllStats")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .sheet(isPresented: $showAll) {
                AllStatsView()
            }
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .kerning(0.5)
            .foregroundStyle(Palette.inkDim)
    }

    // MARK: - 着順表

    /// 1〜4位に加え、5〜6人打ちで5位以下が出た場合はその分も列を増やす
    private var rankColumns: [Int] {
        let highest = stats.flatMap { $0.rankCounts.keys }.max() ?? 0
        return Array(1...max(4, highest))
    }

    /// 濃淡は列ごとではなく、表全体(全プレイヤー×全着順)の最大値を基準にする
    private var heatMax: Int {
        max(1, stats.flatMap { s in rankColumns.map { s.count(ofRank: $0) } }.max() ?? 1)
    }

    private var rankTable: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                Text("").gridColumnAlignment(.leading)
                headerCell("合計")
                ForEach(rankColumns, id: \.self) { headerCell("\($0)位") }
                headerCell("平均")
            }
            .padding(.bottom, 6)

            ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                GridRow {
                    Text(stat.name)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        // 「五十嵐」が「五…」に潰れないよう、名前は縮めない
                        .fixedSize(horizontal: true, vertical: false)
                        .gridColumnAlignment(.leading)
                        .padding(.trailing, 10)

                    Text(ScoreFormatter.string(stat.total, decimalMode: session.decimalMode))
                        .font(.system(size: 12.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(stat.total < 0 ? Palette.negative : Palette.ink)

                    ForEach(rankColumns, id: \.self) { rank in
                        let count = stat.count(ofRank: rank)
                        Text("\(count)")
                            .font(.system(size: 12.5, weight: count > 0 ? .bold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(heatColor(count), in: RoundedRectangle(cornerRadius: 6))
                    }

                    Text(stat.averageRank.map { String(format: "%.2f", $0) } ?? "–")
                        .font(.system(size: 12.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink)
                }
                .padding(.vertical, 2)
                // マス単位で読ませると数字だけが並んで意味が取れない。行ごとにまとめる
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken(stat))
            }
        }
    }

    /// 1行ぶんの読み上げ。項目名を添えないと数字の意味が分からない
    private func spoken(_ stat: PlayerStats) -> String {
        var parts = ["\(stat.name)",
                     "合計 \(ScoreFormatter.signedString(stat.total, decimalMode: session.decimalMode))",
                     "\(stat.played)局"]
        for rank in rankColumns where stat.count(ofRank: rank) > 0 {
            parts.append("\(rank)位 \(stat.count(ofRank: rank))回")
        }
        if let rank = stat.averageRank { parts.append("平均着順 \(String(format: "%.2f", rank))") }
        return parts.joined(separator: "、")
    }

    private func headerCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Palette.inkDim)
            .frame(maxWidth: .infinity)
    }

    /// 0はグレー、件数が多いほど青→赤に寄せる単一のグラデーション
    private func heatColor(_ count: Int) -> Color {
        guard count > 0 else { return Palette.inkDim.opacity(0.10) }
        let t = Double(count) / Double(heatMax)
        let base = t <= 0.5
            ? Palette.inkDim.mix(with: Palette.toneBInk, by: t / 0.5)
            : Palette.toneBInk.mix(with: Palette.negative, by: (t - 0.5) / 0.5)
        return base.opacity(0.20 + t * 0.45)
    }

    // MARK: - 推移グラフ

    private struct Series: Identifiable {
        let id: String
        let color: Color
        let points: [Int]
    }

    private var series: [Series] {
        let cumulative = session.cumulativeTotals()
        return session.players.enumerated().map { index, name in
            Series(
                id: name,
                color: Palette.playerColors[index % Palette.playerColors.count],
                points: index < cumulative.count ? cumulative[index] : []
            )
        }
    }

    private var trendChart: some View {
        Chart {
            ForEach(series) { line in
                ForEach(Array(line.points.enumerated()), id: \.offset) { index, value in
                    LineMark(
                        x: .value("局", index + 1),
                        y: .value("累計", value)
                    )
                    .foregroundStyle(line.color)
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .opacity(opacity(for: line.id))
                }
                .foregroundStyle(by: .value("名前", line.id))
            }
            RuleMark(y: .value("ゼロ", 0))
                .foregroundStyle(Palette.line)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .chartForegroundStyleScale(
            domain: series.map(\.id),
            range: series.map(\.color)
        )
        .chartLegend(.hidden)
        .frame(height: 190)
    }

    private var legend: some View {
        // 凡例をタップするとその人の線だけ残る。もう一度押すと全員に戻る
        FlowRow(spacing: 6) {
            ForEach(series) { line in
                Button {
                    soloed = (soloed == line.id) ? nil : line.id
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(line.color).frame(width: 8, height: 8)
                        Text(line.id)
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(Palette.ink)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Palette.surface, in: Capsule())
                    .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
                    .opacity(soloed == nil || soloed == line.id ? 1 : 0.35)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func opacity(for name: String) -> Double {
        guard let soloed else { return 1 }
        return soloed == name ? 1 : 0.12
    }
}

/// 凡例を折り返して並べるだけの簡単なレイアウト
private struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
