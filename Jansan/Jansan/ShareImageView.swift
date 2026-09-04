import SwiftUI
import Charts
import JansanCore

/// LINEなどに貼るための画像を3枚作る。
///
/// **縦長1枚にしない。** トークのプレビューで縮小されて数字が読めず、
/// 開かないと分からない画像は結局見られない。3:4 を3枚に分ける。
/// 複数枚まとめて送れるので、送る手間は変わらない。
///
/// 各画像の上にタイトルと期間を必ず入れる。1枚だけ転送されることがあるため。
struct ShareImageView: View {
    let title: String
    let subtitle: String

    /// ①直近の対局 ②期間の累計 ③推移と統計
    enum Kind: Int, CaseIterable, Identifiable {
        case latest, totals, trend
        var id: Int { rawValue }
        var caption: String {
            switch self {
            case .latest: "直近の対局"
            case .totals: "累計"
            case .trend: "推移"
            }
        }
    }

    let kind: Kind
    let rows: [Row]
    let series: [(name: String, color: Color, points: [Int])]
    let decimalMode: Bool

    /// 1行ぶんの表示内容。画像を描くだけなので、集計の型とは切り離しておく
    struct Row: Identifiable {
        let id = UUID()
        let name: String
        let color: Color
        /// 左から並べる値。見出しは `headers` と対応する
        let values: [String]
        let isNegative: [Bool]
    }

    let headers: [String]

    /// 3:4。共有シートと写真アプリでそのまま扱える大きさ
    static let size = CGSize(width: 900, height: 1200)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Palette.line)
            // 行が少ないと下が大きく空く。上下に余白を分けて、表を縦の真ん中に置く
            Spacer(minLength: 22)
            content
            Spacer(minLength: 22)
            footer
        }
        .padding(34)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Palette.bg)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Palette.ink)
            HStack(spacing: 10) {
                Text(kind.caption)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Palette.accentInk)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Palette.accent, in: Capsule())
                Text(subtitle)
                    .font(.system(size: 20))
                    .foregroundStyle(Palette.inkDim)
            }
        }
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .latest, .totals:
            table
        case .trend:
            VStack(alignment: .leading, spacing: 24) {
                chart
                table
            }
        }
    }

    private var table: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                Text("").gridColumnAlignment(.leading)
                ForEach(headers, id: \.self) { head in
                    Text(head)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Palette.inkDim)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 12)

            ForEach(rows) { row in
                GridRow {
                    HStack(spacing: 10) {
                        Circle().fill(row.color).frame(width: 14, height: 14)
                        Text(row.name)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .gridColumnAlignment(.leading)
                    .padding(.trailing, 16)

                    ForEach(Array(row.values.enumerated()), id: \.offset) { index, value in
                        Text(value)
                            .font(.system(size: 26, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(row.isNegative.indices.contains(index) && row.isNegative[index]
                                             ? Palette.negative : Palette.ink)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 10)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 6)
            }
        }
    }

    private struct Point: Identifiable {
        let index: Int
        let value: Int
        var id: Int { index }
    }

    private var chart: some View {
        Chart {
            ForEach(Array(series.enumerated()), id: \.offset) { _, line in
                ForEach(points(line.points)) { point in
                    LineMark(x: .value("対局", point.index), y: .value("累計", point.value))
                        .foregroundStyle(line.color)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: 330)
    }

    private func points(_ values: [Int]) -> [Point] {
        ([0] + values).enumerated().map { Point(index: $0.offset, value: $0.element) }
    }

    private var footer: some View {
        HStack {
            Text("雀算")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Palette.accent)
            Spacer()
            Text(Date.now.formatted(.dateTime.year().month().day().locale(Locale(identifier: "ja_JP"))))
                .font(.system(size: 16))
                .foregroundStyle(Palette.inkDim)
        }
        .padding(.top, 16)
    }
}
