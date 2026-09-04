import SwiftUI
import JansanCore

struct ScoreTableView: View {
    let board: ScoreBoard

    /// Noをタップした局。確認してから消す
    @State private var pendingRemoval: Int?

    // 局数が中くらいのときは行が画面を埋めるので、この値が効くのは
    // 「文字に対して行をどれだけ厚くするか」の比と、縮小が止まったあとの高さだけ。
    // 大きくすると倍率の分母が増え、行の高さはそのままに文字だけ小さくなる
    private let baseRowHeight: CGFloat = 34
    private let baseHeaderHeight: CGFloat = 30
    /// 端末の文字サイズ設定に追従させる。
    ///
    /// **表は列数ぶんを横に並べる必要があるので、無制限には大きくできない。**
    /// 大きくしすぎると数字が「32…」と潰れ、読めるどころか読めなくなる。
    /// そこで @ScaledMetric で追従はさせたうえで、下の metrics(_:) の
    /// maxTextScale で頭打ちにしている。
    /// それでも足りない人には、読み上げ（VoiceOver）で全部の値が読める。
    @ScaledMetric(relativeTo: .body) private var baseFontSize: CGFloat = 14.5
    private let noColumnWidth: CGFloat = 30

    /// 文字と見出しを大きくする上限。ここから先は行の高さだけを伸ばす。
    /// 局数が少ないだけで文字までどんどん太らせると、表ではなく看板になる
    private let maxTextScale: CGFloat = 1.45
    /// これ以上縮めると数字が読めないので、あとはスクロールに任せる
    private let minScale: CGFloat = 0.55

    var body: some View {
        // board.session は描画の途中でも差し替わりうる(記録の読み込み、人数変更)。
        // ForEach の中身は遅延評価されるため、都度読み直すと
        // 「行を組んだ時点の人数」と「マスを描く時点の人数」がズレて範囲外アクセスになる。
        // ここで一度だけ読み、以降は添字ではなく値そのものを渡していく。
        let session = board.session

        GeometryReader { geometry in
            let layout = metrics(
                roundCount: session.rounds.count,
                columns: session.players.count,
                size: geometry.size
            )
            let scale = layout.scale
            // 名前の行と合計の行は常に見えていてほしいので、スクロールするのは中身だけ
            let chrome = baseHeaderHeight * scale * 2
            let available = max(0, geometry.size.height - chrome)
            let required = layout.rowHeight * CGFloat(session.rounds.count)

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
                                    scale: scale,
                                    height: layout.rowHeight
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
            Text("以降の局が繰り上がります。この操作は元に戻せません。")
        }
    }

    /// プロトタイプの fitRows の置き換え。
    /// あちらは実際の高さを測りながら --scale を 0.04 ずつ下げるループだったが、
    /// 必要な高さは行数から計算できるので、SwiftUIでは一度で倍率を出せる。
    ///
    /// 文字の倍率と行の高さを分けて返す。
    /// 全体を同じ倍率で伸縮させるだけだと、局数が少ないときに表が上の数分の一に
    /// 貼り付いたまま下が丸ごと余る。かといって文字ごと拡大すると表が看板になる。
    /// そこで文字と見出しは maxTextScale で頭打ちにし、**余った高さは行にだけ配る。**
    ///
    /// 行を伸ばすのはマスが正方形になるところまで。それ以上は数字がぽつんと浮いた
    /// 縦長のマスになって、埋まっているのに読みにくいという逆転が起きる。
    ///
    /// No列の幅は3種類の行すべてで scale を使う。ここに行ごとの倍率を混ぜると
    /// 見出しと中身で列がずれる。
    private func metrics(roundCount: Int, columns: Int, size: CGSize) -> (scale: CGFloat, rowHeight: CGFloat) {
        guard size.height > 0, size.width > 0, roundCount > 0, columns > 0 else {
            return (1, baseRowHeight)
        }
        let rows = CGFloat(roundCount)
        let uniform = size.height / (baseHeaderHeight * 2 + baseRowHeight * rows)
        let scale = min(maxTextScale, max(minScale, uniform))

        // 見出しと合計を置いた残りを行数で割る。局数が多ければ基準の高さのまま溢れさせ、
        // スクロールに任せる(min ではなく max を取っているのはそのため)
        let leftover = max(0, size.height - baseHeaderHeight * scale * 2)
        let filled = max(baseRowHeight * scale, leftover / rows)
        let square = (size.width - noColumnWidth * scale) / CGFloat(columns)
        return (scale, min(filled, square))
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

    private func scoreRow(round: Round, index: Int, decimalMode: Bool, scale: CGFloat, height: CGFloat) -> some View {
        let highlight = round.topAndLastColumns
        let isUnbalanced = round.isUnbalanced
        return HStack(spacing: 0) {
            // 局番号は行の取っ手も兼ねる。タップすると削除の確認が出る
            // 合計が0にならない局は番号を赤くして知らせる
            Text(isUnbalanced ? "!" : "\(index + 1)")
                .font(.system(size: 12 * scale, weight: isUnbalanced ? .heavy : .semibold))
                .foregroundStyle(isUnbalanced ? Palette.negative : Palette.inkDim)
                .frame(width: noColumnWidth * scale)
                .frame(maxHeight: .infinity)
                .background(isUnbalanced ? Palette.lastTint : Palette.bg)
                .contentShape(Rectangle())
                .onTapGesture { pendingRemoval = index }
                .accessibilityElement()
                .accessibilityLabel("\(index + 1)局目")
                .accessibilityValue(isUnbalanced ? "合計が0になっていません" : "")
                .accessibilityHint("タップするとこの局を削除できます")
                .accessibilityAddTraits(.isButton)
            ForEach(Array(round.entries.enumerated()), id: \.offset) { column, entry in
                cell(
                    entry: entry,
                    position: Position(round: index, column: column),
                    playerName: board.session.players.indices.contains(column)
                        ? board.session.players[column] : "\(column + 1)人目",
                    isTop: highlight?.top.contains(column) ?? false,
                    isLast: highlight?.last.contains(column) ?? false,
                    decimalMode: decimalMode,
                    scale: scale
                )
            }
        }
        .frame(height: height)
        .overlay(alignment: .bottom) { hairline }
    }

    private func totalsRow(totals: [Int], decimalMode: Bool, scale: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text("合計")
                .font(.system(size: 12.5 * scale, weight: .heavy))
                .foregroundStyle(Palette.inkDim)
                .frame(width: noColumnWidth * scale)
            ForEach(Array(totals.enumerated()), id: \.offset) { column, total in
                Text(ScoreFormatter.string(total, decimalMode: decimalMode))
                    .font(.system(size: baseFontSize * scale, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(total < 0 ? Palette.negative : Palette.ink)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(
                        board.session.players.indices.contains(column)
                            ? "\(board.session.players[column]) の合計" : "合計"
                    )
                    .accessibilityValue(ScoreFormatter.signedString(total, decimalMode: decimalMode))
            }
        }
        .frame(height: baseHeaderHeight * scale)
        .background(Palette.surface2)
        .overlay(alignment: .top) { hairline }
    }

    // MARK: - マス

    private func cell(
        entry: Entry,
        position: Position,
        playerName: String,
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
            // 画面では「·」「－」としか出ないので、読み上げには意味の分かる言葉を渡す
            .accessibilityElement()
            .accessibilityIdentifier("cell-\(position.round)-\(position.column)")
            .accessibilityLabel("\(playerName) \(position.round + 1)局目")
            .accessibilityValue(spokenValue(entry: entry, preview: preview, decimalMode: decimalMode))
            .accessibilityHint(isSelected ? "選択中です" : "タップして点数を入力")
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// 読み上げ用の言い換え。記号のまま読ませると意味が伝わらない
    private func spokenValue(entry: Entry, preview: Int?, decimalMode: Bool) -> String {
        if let preview { return "入力中 \(ScoreFormatter.string(preview, decimalMode: decimalMode))" }
        if entry.isResting { return "お休み" }
        guard let value = entry.value else { return "未入力" }
        let body = ScoreFormatter.string(value, decimalMode: decimalMode)
        // 「自動で入った」ことが分からないと、消していいマスかどうか判断できない
        return entry == .derived(value) ? "\(body) 自動計算" : body
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
