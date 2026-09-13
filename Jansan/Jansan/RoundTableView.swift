import SwiftUI
import JansanCore

/// 1回の対局の表（局ごとの点数と合計）。入力画面の表と同じ情報を、触れない形で見せる。
///
/// 保存した記録の画面と、集計の「最近の記録」（とその画像）で使う。
/// - `fitsWidth: false` … 人数が多いと横に送る（記録の画面）
/// - `fitsWidth: true` … 画面の幅に収める。**画像にするときは横に送る ScrollView を使えない**
///   （`ImageRenderer` は ScrollView の中身を描かない）
struct RoundTableView: View {
    let session: Session
    var fitsWidth = false

    private static let indexWidth: CGFloat = 34
    private static let columnWidth: CGFloat = 76

    var body: some View {
        if fitsWidth {
            grid
        } else {
            ScrollView(.horizontal, showsIndicators: false) { grid }
        }
    }

    private var grid: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                cell("局", weight: .heavy, color: Palette.inkDim, isIndex: true)
                ForEach(Array(session.players.enumerated()), id: \.offset) { _, name in
                    cell(name, weight: .heavy, color: Palette.ink, isIndex: false)
                }
            }
            .background(Palette.surface2)

            ForEach(Array(session.rounds.enumerated()), id: \.offset) { index, round in
                // 入力待ちの空行は見せない。眺める画面に空欄は要らない
                if round.entries.contains(where: { $0.value != nil || $0.isResting }) {
                    GridRow {
                        cell("\(index + 1)", weight: .semibold, color: Palette.inkDim, isIndex: true)
                        ForEach(Array(round.entries.enumerated()), id: \.offset) { column, entry in
                            let highlight = round.topAndLastColumns
                            cell(text(for: entry),
                                 weight: .semibold,
                                 color: color(for: entry,
                                              isTop: highlight?.top.contains(column) ?? false,
                                              isLast: highlight?.last.contains(column) ?? false),
                                 isIndex: false)
                        }
                    }
                }
            }

            GridRow {
                cell("合計", weight: .heavy, color: Palette.inkDim, isIndex: true)
                ForEach(Array(session.totals.enumerated()), id: \.offset) { _, total in
                    cell(ScoreFormatter.string(total, decimalMode: session.decimalMode),
                         weight: .heavy,
                         color: total < 0 ? Palette.negative : Palette.ink,
                         isIndex: false)
                }
            }
            .background(Palette.surface2)
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line))
    }

    @ViewBuilder
    private func cell(_ text: String, weight: Font.Weight, color: Color, isIndex: Bool) -> some View {
        let label = Text(text)
            .font(.system(size: 14, weight: weight))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        if isIndex || !fitsWidth {
            label.frame(width: isIndex ? Self.indexWidth : Self.columnWidth, height: 32)
        } else {
            label.frame(maxWidth: .infinity).frame(height: 32)
        }
    }

    private func text(for entry: Entry) -> String {
        if entry.isResting { return "－" }
        guard let value = entry.value else { return "" }
        return ScoreFormatter.string(value, decimalMode: session.decimalMode)
    }

    private func color(for entry: Entry, isTop: Bool, isLast: Bool) -> Color {
        if entry.isResting { return Palette.resting }
        guard let value = entry.value else { return Palette.inkDim }
        if isTop { return Palette.topInk }
        if isLast || value < 0 { return Palette.negative }
        return Palette.ink
    }
}
