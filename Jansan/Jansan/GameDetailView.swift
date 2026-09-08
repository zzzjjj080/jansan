import SwiftUI
import Charts
import JansanCore

/// 保存した対局を**眺めるだけ**の画面。
///
/// 記録をタップすると、以前は入力中の表が丸ごと置き換わっていた。
/// 「見たいだけ」と「続きを打ちたい」は別の用件なので、既定は見るだけにする。
///
/// **入力画面とは見た目をはっきり変える。** 同じ表が出ると触れると思ってしまう。
/// 地の色を落とし、マスに枠を出さず、上に「見るだけ」の帯を出す。
struct GameDetailView: View {
    let record: SavedGame
    let directory: Directory
    let board: ScoreBoard
    var goToInput: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var snapshot: GameSnapshot?
    @State private var loadConfirm = false

    private var decimalMode: Bool { record.decimalMode }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    banner
                    if let snapshot {
                        headline(snapshot)
                        table(snapshot.session)
                        ranking(snapshot.session)
                        trend(snapshot.session)
                    } else {
                        ContentUnavailableView("この記録は開けませんでした", systemImage: "exclamationmark.triangle")
                            .padding(.top, 40)
                    }
                }
                .padding(16)
            }
            .background(Palette.bg)
            .navigationTitle(record.dateLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
                if directory.isEditable {
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            loadConfirm = true
                        } label: {
                            Label("この表を入力に読み込む", systemImage: "square.and.pencil")
                        }
                        .accessibilityIdentifier("loadIntoInput")
                    }
                }
            }
            .alert("入力に読み込みますか", isPresented: $loadConfirm) {
                Button("キャンセル", role: .cancel) {}
                Button("読み込む") {
                    board.load(record)
                    dismiss()
                    goToInput()
                }
            } message: {
                Text("いま入力中の表は置き換わります。取り消しから元に戻せます。")
            }
        }
        .onAppear { snapshot = try? record.snapshot() }
    }

    /// 「これは触れない」と一目で分かる帯。入力画面と取り違えないための目印
    private var banner: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.fill")
            Text(directory.isSubscribed ? "共有された記録・見るだけ" : "保存した記録・見るだけ")
                .font(.footnote.weight(.bold))
            Spacer()
        }
        .foregroundStyle(Palette.inkDim)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Palette.surface2, in: Capsule())
    }

    private func headline(_ snapshot: GameSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.shapeLabel)
                .font(.headline)
                .foregroundStyle(Palette.ink)
            if !record.note.isEmpty {
                Label(record.note, systemImage: "text.quote")
                    .font(.subheadline)
                    .foregroundStyle(Palette.toneAInk)
            }
            if record.hasCustomPlayedAt {
                Text("保存日時 \(record.savedAtLabel)")
                    .font(.caption)
                    .foregroundStyle(Palette.inkDim)
            }
        }
    }

    // MARK: - 表（触れない）

    private func table(_ session: Session) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    cell("局", weight: .heavy, color: Palette.inkDim, width: 34)
                    ForEach(Array(session.players.enumerated()), id: \.offset) { _, name in
                        cell(name, weight: .heavy, color: Palette.ink, width: 76)
                    }
                }
                .background(Palette.surface2)

                ForEach(Array(session.rounds.enumerated()), id: \.offset) { index, round in
                    // 入力待ちの空行は見せない。眺める画面に空欄は要らない
                    if round.entries.contains(where: { $0.value != nil || $0.isResting }) {
                        GridRow {
                            cell("\(index + 1)", weight: .semibold, color: Palette.inkDim, width: 34)
                            ForEach(Array(round.entries.enumerated()), id: \.offset) { column, entry in
                                let highlight = round.topAndLastColumns
                                cell(text(for: entry),
                                     weight: .semibold,
                                     color: color(for: entry,
                                                  isTop: highlight?.top.contains(column) ?? false,
                                                  isLast: highlight?.last.contains(column) ?? false),
                                     width: 76)
                            }
                        }
                    }
                }

                GridRow {
                    cell("合計", weight: .heavy, color: Palette.inkDim, width: 34)
                    ForEach(Array(session.totals.enumerated()), id: \.offset) { _, total in
                        cell(ScoreFormatter.string(total, decimalMode: decimalMode),
                             weight: .heavy,
                             color: total < 0 ? Palette.negative : Palette.ink,
                             width: 76)
                    }
                }
                .background(Palette.surface2)
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line))
        }
    }

    private func cell(_ text: String, weight: Font.Weight, color: Color, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 14, weight: weight))
            .monospacedDigit()
            .foregroundStyle(color)
            .frame(width: width, height: 32)
    }

    private func text(for entry: Entry) -> String {
        if entry.isResting { return "－" }
        guard let value = entry.value else { return "" }
        return ScoreFormatter.string(value, decimalMode: decimalMode)
    }

    private func color(for entry: Entry, isTop: Bool, isLast: Bool) -> Color {
        if entry.isResting { return Palette.resting }
        guard let value = entry.value else { return Palette.inkDim }
        if isTop { return Palette.topInk }
        if isLast || value < 0 { return Palette.negative }
        return Palette.ink
    }

    // MARK: - 着順と推移

    private func ranking(_ session: Session) -> some View {
        let stats = session.playerStats().filter { $0.played > 0 }
        return VStack(alignment: .leading, spacing: 8) {
            Text("成績").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.inkDim)
            ForEach(Array(stats.sorted { $0.total > $1.total }.enumerated()), id: \.offset) { index, stat in
                HStack {
                    Text("\(index + 1)位").font(.caption.weight(.bold)).foregroundStyle(Palette.inkDim).frame(width: 34, alignment: .leading)
                    Text(stat.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    Spacer()
                    Text("平着 \(stat.averageRank.map { String(format: "%.2f", $0) } ?? "–")")
                        .font(.caption).foregroundStyle(Palette.inkDim)
                    Text(ScoreFormatter.signedString(stat.total, decimalMode: decimalMode))
                        .font(.subheadline.weight(.bold)).monospacedDigit()
                        .foregroundStyle(stat.total < 0 ? Palette.negative : Palette.ink)
                        .frame(width: 66, alignment: .trailing)
                }
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private struct Point: Identifiable {
        let index: Int, value: Int
        let name: String
        var id: String { "\(name)-\(index)" }
    }

    private func trend(_ session: Session) -> some View {
        let cumulative = session.cumulativeTotals()
        let points = session.players.enumerated().flatMap { column, name in
            ([0] + (cumulative.indices.contains(column) ? cumulative[column] : []))
                .enumerated().map { Point(index: $0.offset, value: $0.element, name: name) }
        }
        let colors = session.players.enumerated().map { index, _ in
            Palette.playerColors[index % Palette.playerColors.count]
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text("推移（局ごとの累計）").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.inkDim)
            Chart(points) { point in
                // series: が無いと全員の点が1本に繋がる
                LineMark(x: .value("局", point.index), y: .value("累計", point.value),
                         series: .value("名前", point.name))
                    .foregroundStyle(by: .value("名前", point.name))
            }
            .chartForegroundStyleScale(domain: session.players, range: colors)
            .frame(height: 180)
        }
    }
}
