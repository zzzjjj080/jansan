import SwiftUI
import JansanCore

struct ScoreTableView: View {
    let board: ScoreBoard

    /// Noをタップした局。確認してから消す
    @State private var pendingRemoval: Int?

    private let baseRowHeight: CGFloat = 34
    private let baseHeaderHeight: CGFloat = 30
    private let baseRankHeight: CGFloat = 22
    private let baseFontSize: CGFloat = 14.5
    private let noColumnWidth: CGFloat = 30

    var body: some View {
        // board.session は描画の途中でも差し替わりうる(記録の読み込み、人数変更)。
        // ForEach の中身は遅延評価されるため、都度読み直すと
        // 「行を組んだ時点の人数」と「マスを描く時点の人数」がズレて範囲外アクセスになる。
        // ここで一度だけ読み、以降は添字ではなく値そのものを渡していく。
        let session = board.session

        GeometryReader { geometry in
            let scale = fitScale(roundCount: session.rounds.count, height: geometry.size.height)
            // 名前・合計・順位の行は常に見えていてほしいので、スクロールするのは中身だけ
            let chrome = (baseHeaderHeight * 2 + baseRankHeight) * scale
            let available = max(0, geometry.size.height - chrome)
            let required = baseRowHeight * scale * CGFloat(session.rounds.count)

            VStack(spacing: 0) {
                headerRow(players: session.players, scale: scale)

                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(spacing: 0) {
                            ForEach(Array(session.rounds.enumerated()), id: \.offset) { index, round in
                                scoreRow(
                                    round: round,
                                    index: index,
                                    decimalMode: session.decimalMode,
                                    scale: scale
                                )
                                .id(index)
                            }
                        }
                    }
                    // 収まるうちは行の分だけの高さにして、合計行を直下に置く
                    .frame(height: min(available, required))
                    .onChange(of: board.selection) { _, selection in
                        guard let selection else { return }
                        withAnimation { proxy.scrollTo(selection.round, anchor: .center) }
                    }
                    .onChange(of: session.rounds.count) { _, count in
                        withAnimation { proxy.scrollTo(count - 1, anchor: .bottom) }
                    }
                }

                totalsRow(totals: session.totals, decimalMode: session.decimalMode, scale: scale)
                rankingRow(rankings: session.rankings(), scale: scale)
                Spacer(minLength: 0)
            }
        }
        .confirmationDialog(
            pendingRemoval.map { "\($0 + 1)局目を削除しますか" } ?? "",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("この局を削除", role: .destructive) {
                if let index = pendingRemoval { board.removeRound(at: index) }
                pendingRemoval = nil
            }
            Button("キャンセル", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("以降の局が繰り上がります。消したあとでも、テンキー上部の取り消しボタンで戻せます。")
        }
    }

    /// プロトタイプの fitRows の置き換え。
    /// あちらは実際の高さを測りながら --scale を 0.04 ずつ下げるループだったが、
    /// 必要な高さは行数から計算できるので、SwiftUIでは一度で倍率を出せる。
    ///
    /// 0.55 より小さくすると数字が読めなくなるので、そこから先は縮めずスクロールに任せる。
    private func fitScale(roundCount: Int, height: CGFloat) -> CGFloat {
        guard height > 0 else { return 1 }
        let required = baseHeaderHeight * 2 + baseRankHeight + baseRowHeight * CGFloat(roundCount)
        return min(1, max(0.55, height / required))
    }

    // MARK: - 行

    private func headerRow(players: [String], scale: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("No")
                .font(.system(size: 11 * scale, weight: .heavy))
                .foregroundStyle(Palette.inkDim)
                .frame(width: noColumnWidth * scale)
            ForEach(Array(players.enumerated()), id: \.offset) { _, name in
                Text(name)
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

    private func scoreRow(round: Round, index: Int, decimalMode: Bool, scale: CGFloat) -> some View {
        let highlight = round.topAndLastColumns
        return HStack(spacing: 0) {
            // 局番号は行の取っ手も兼ねる。タップすると削除の確認が出る
            Text("\(index + 1)")
                .font(.system(size: 12 * scale, weight: .semibold))
                .foregroundStyle(Palette.inkDim)
                .frame(width: noColumnWidth * scale)
                .frame(maxHeight: .infinity)
                .background(Palette.bg)
                .contentShape(Rectangle())
                .onTapGesture { pendingRemoval = index }
            ForEach(Array(round.entries.enumerated()), id: \.offset) { column, entry in
                cell(
                    entry: entry,
                    position: Position(round: index, column: column),
                    isTop: highlight?.top.contains(column) ?? false,
                    isLast: highlight?.last.contains(column) ?? false,
                    decimalMode: decimalMode,
                    scale: scale
                )
            }
        }
        .frame(height: baseRowHeight * scale)
        .overlay(alignment: .bottom) { hairline }
    }

    private func totalsRow(totals: [Int], decimalMode: Bool, scale: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("合計")
                .font(.system(size: 12.5 * scale, weight: .heavy))
                .foregroundStyle(Palette.inkDim)
                .frame(width: noColumnWidth * scale)
            ForEach(Array(totals.enumerated()), id: \.offset) { _, total in
                Text(ScoreFormatter.string(total, decimalMode: decimalMode))
                    .font(.system(size: baseFontSize * scale, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(total < 0 ? Palette.negative : Palette.ink)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: baseHeaderHeight * scale)
        .background(Palette.surface2)
        .overlay(alignment: .top) { hairline }
    }

    /// 今の合計での順位。対局中に一番よく聞かれる「今トップは誰か」に答えるための行
    private func rankingRow(rankings: [Int], scale: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("順位")
                .font(.system(size: 10.5 * scale, weight: .bold))
                .foregroundStyle(Palette.inkDim)
                .frame(width: noColumnWidth * scale)
            ForEach(Array(rankings.enumerated()), id: \.offset) { _, rank in
                Text("\(rank)")
                    .font(.system(size: 11.5 * scale, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(rank == 1 ? Palette.accentInk : Palette.inkDim)
                    .frame(minWidth: 17 * scale, minHeight: 17 * scale)
                    .background {
                        if rank == 1 { Circle().fill(Palette.accent) }
                    }
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: baseRankHeight * scale)
        .background(Palette.surface2)
    }

    // MARK: - マス

    private func cell(
        entry: Entry,
        position: Position,
        isTop: Bool,
        isLast: Bool,
        decimalMode: Bool,
        scale: CGFloat
    ) -> some View {
        let isSelected = board.selection == position
        let preview = isSelected ? board.pendingValue : nil

        return Text(label(for: entry, preview: preview, decimalMode: decimalMode))
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

    private func label(for entry: Entry, preview: Int?, decimalMode: Bool) -> String {
        if let preview {
            return ScoreFormatter.string(preview, decimalMode: decimalMode)
        }
        if entry.isResting { return "－" }
        guard let value = entry.value else { return "·" }
        return ScoreFormatter.string(value, decimalMode: decimalMode)
    }

    private func foreground(entry: Entry, preview: Int?, isTop: Bool, isLast: Bool) -> Color {
        // 入力中でもマイナスかどうかが一目で分かるように、符号で色を変える
        if let preview { return preview < 0 ? Palette.negative : Palette.toneBInk }
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
