import SwiftUI
import JansanCore

struct ScoreTableView: View {
    let board: ScoreBoard

    private let baseRowHeight: CGFloat = 34
    private let baseHeaderHeight: CGFloat = 30
    private let baseFontSize: CGFloat = 14.5
    private let noColumnWidth: CGFloat = 30

    private var session: Session { board.session }

    var body: some View {
        GeometryReader { geometry in
            let scale = fitScale(forHeight: geometry.size.height)
            VStack(spacing: 0) {
                headerRow(scale: scale)
                ForEach(session.rounds.indices, id: \.self) { round in
                    scoreRow(round: round, scale: scale)
                }
                totalsRow(scale: scale)
                Spacer(minLength: 0)
            }
        }
    }

    /// プロトタイプの fitRows の置き換え。
    /// あちらは実際の高さを測りながら --scale を 0.04 ずつ下げるループだったが、
    /// 必要な高さは行数から計算できるので、SwiftUIでは一度で倍率を出せる。
    private func fitScale(forHeight height: CGFloat) -> CGFloat {
        guard height > 0 else { return 1 }
        let required = baseHeaderHeight * 2 + baseRowHeight * CGFloat(session.rounds.count)
        return min(1, max(0.55, height / required))
    }

    // MARK: - 行

    private func headerRow(scale: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("No")
                .font(.system(size: 11 * scale, weight: .heavy))
                .foregroundStyle(Palette.inkDim)
                .frame(width: noColumnWidth * scale)
            ForEach(session.players.indices, id: \.self) { column in
                Text(session.players[column])
                    .font(.system(size: 13 * scale, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: baseHeaderHeight * scale)
        .background(Palette.surface2)
        .overlay(alignment: .bottom) { hairline }
    }

    private func scoreRow(round: Int, scale: CGFloat) -> some View {
        let highlight = session.rounds[round].topAndLastColumns
        return HStack(spacing: 0) {
            Text("\(round + 1)")
                .font(.system(size: 12 * scale, weight: .semibold))
                .foregroundStyle(Palette.inkDim)
                .frame(width: noColumnWidth * scale)
                .frame(maxHeight: .infinity)
                .background(Palette.bg)
            ForEach(session.players.indices, id: \.self) { column in
                cell(round: round, column: column, highlight: highlight, scale: scale)
            }
        }
        .frame(height: baseRowHeight * scale)
        .overlay(alignment: .bottom) { hairline }
    }

    private func totalsRow(scale: CGFloat) -> some View {
        let totals = session.totals
        return HStack(spacing: 0) {
            Text("合計")
                .font(.system(size: 12.5 * scale, weight: .heavy))
                .foregroundStyle(Palette.inkDim)
                .frame(width: noColumnWidth * scale)
            ForEach(totals.indices, id: \.self) { column in
                Text(ScoreFormatter.string(totals[column], decimalMode: session.decimalMode))
                    .font(.system(size: baseFontSize * scale, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(totals[column] < 0 ? Palette.negative : Palette.ink)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: baseHeaderHeight * scale)
        .background(Palette.surface2)
        .overlay(alignment: .top) { hairline }
    }

    // MARK: - マス

    private func cell(round: Int, column: Int, highlight: (top: [Int], last: [Int])?, scale: CGFloat) -> some View {
        let position = Position(round: round, column: column)
        let entry = session.rounds[round].entries[column]
        let isSelected = board.selection == position
        let preview = isSelected ? board.pendingValue : nil
        let isTop = highlight?.top.contains(column) ?? false
        let isLast = highlight?.last.contains(column) ?? false

        return Text(label(for: entry, preview: preview))
            .font(.system(size: baseFontSize * scale, weight: preview != nil ? .heavy : .semibold))
            .monospacedDigit()
            .foregroundStyle(foreground(entry: entry, preview: preview, isTop: isTop, isLast: isLast))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background(entry: entry, preview: preview, isTop: isTop, isLast: isLast))
            .overlay {
                if isSelected {
                    Rectangle()
                        .strokeBorder(preview != nil ? Palette.toneBInk : Palette.accent, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { board.tap(position) }
    }

    private func label(for entry: Entry, preview: Int?) -> String {
        if let preview {
            return ScoreFormatter.string(preview, decimalMode: session.decimalMode)
        }
        if entry.isResting { return "－" }
        guard let value = entry.value else { return "·" }
        return ScoreFormatter.string(value, decimalMode: session.decimalMode)
    }

    private func foreground(entry: Entry, preview: Int?, isTop: Bool, isLast: Bool) -> Color {
        if preview != nil { return Palette.toneBInk }
        if entry.isResting { return Palette.resting }
        guard let value = entry.value else { return Palette.inkDim }
        if isTop { return Palette.topInk }
        if isLast || value < 0 { return Palette.negative }
        return Palette.ink
    }

    private func background(entry: Entry, preview: Int?, isTop: Bool, isLast: Bool) -> Color {
        if preview != nil { return Palette.toneB }
        if entry.isResting { return Palette.restingBg }
        if isTop { return Palette.topTint }
        if isLast { return Palette.lastTint }
        return Palette.surface
    }

    private var hairline: some View {
        Rectangle().fill(Palette.line).frame(height: 0.5)
    }
}
