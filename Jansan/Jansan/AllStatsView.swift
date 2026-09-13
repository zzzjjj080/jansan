import SwiftUI
import SwiftData
import Charts
import JansanCore

/// 個人成績の画面を、誰のページから開くか
private struct PlayerPage: Hashable {
    let start: String
}

/// 保存した記録をまたいだ集計。ディレクトリごとに開く。
///
/// **打ち方（三麻/四麻）で必ず分ける。** 着順の分母が変わるので、混ぜた数字は比べられない。
/// **人数では分けない。** 5人で回す四麻も四麻で、「5人打ち」という打ち方は無い。
/// 表示モードも分ける（混ぜると10倍ズレる）。
struct AllStatsView: View {
    /// 絞るディレクトリ。nil なら全部
    var directory: Directory? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @Query(filter: #Predicate<SavedGame> { !$0.isDraft }, sort: \SavedGame.savedAt, order: .reverse)
    private var allRecords: [SavedGame]

    private var records: [SavedGame] {
        guard let directory else { return allRecords }
        return allRecords.filter { ($0.directoryId ?? Directory.defaultUID) == directory.uid }
    }

    @State private var period: Period = .all
    @State private var style: Int?
    @State private var decimalMode: Bool?
    @State private var soloed: String?
    @State private var showImages = false

    /// 画面に出す期間の選択肢。Core の StatsPeriod は custom を持つが、
    /// ここでは日付の入力欄を作らず、よく使う範囲だけに絞る
    private enum Period: String, CaseIterable, Identifiable {
        case all, last30, thisYear
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: "全期間"
            case .last30: "最近30日"
            case .thisYear: "今年"
            }
        }
        var core: StatsPeriod {
            switch self {
            case .all: .all
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

    /// 1回の描画で1度だけ数える。プロパティのままだと、表・ハイライト・グラフが
    /// それぞれ全対局を数え直す
    private struct Computed {
        let selected: [GameForStats]
        /// 初めて出てきた順。色の割り当てはこの並びで決める（表を並べ替えても色が変わらない）
        let reports: [PlayerReport]
        /// 合計の多い順。表に使う
        let ranked: [PlayerReport]
        let roundCount: Int
        let unknownDateGames: Int
        let seats: Int
        let decimalMode: Bool
        let series: [Series]
        /// 色の割り当て。**このディレクトリの全記録（全期間・三麻と四麻の両方）で初めて出てきた順。**
        /// 期間や打ち方を切り替えるたびに並びが変わると、同じ人の色まで変わってしまう
        let colorOrder: [String]

        func color(_ name: String) -> Color {
            let index = colorOrder.firstIndex(of: name) ?? colorOrder.count
            return Palette.playerColors[index % Palette.playerColors.count]
        }
    }

    private func compute() -> Computed {
        let all = games
        let colorOrder = Report.players(games: all).map(\.name)
        let selected = Report.select(games: all, period: period.core, style: style, decimalMode: decimalMode)
        let reports = Report.players(games: selected)
        let ranked = reports.enumerated()
            .sorted { $0.element.total != $1.element.total ? $0.element.total > $1.element.total : $0.offset < $1.offset }
            .map(\.element)
        let decimal = decimalMode ?? (selected.filter(\.session.decimalMode).count * 2 > selected.count)
        let seats = style ?? max(3, reports.map(\.rankCounts.count).max() ?? 4)
        // 期間で絞ったときに落ちた「日付未記入」の対局。黙って消えると件数が合わない
        let unknown = period == .all ? 0 : Report.select(games: all, style: style, decimalMode: decimalMode)
            .filter { PlayedDate.isUnknown($0.playedAt) }.count

        let partial = Computed(selected: selected, reports: reports, ranked: ranked,
                               roundCount: Report.roundCount(games: selected), unknownDateGames: unknown,
                               seats: seats, decimalMode: decimal, series: [], colorOrder: colorOrder)
        let series = Aggregator.cumulative(games: selected).map { item in
            Series(id: item.name, color: partial.color(item.name), points: item.values)
        }
        return Computed(selected: selected, reports: reports, ranked: ranked,
                        roundCount: partial.roundCount, unknownDateGames: unknown,
                        seats: seats, decimalMode: decimal, series: series, colorOrder: colorOrder)
    }

    private var hasMixedDecimalModes: Bool {
        Set(games.map(\.session.decimalMode)).count > 1
    }

    var body: some View {
        let data = compute()
        let styles = Report.availableStyles(games: games)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    filters(styles: styles)
                    if records.isEmpty {
                        ContentUnavailableView(
                            "まだ記録がありません",
                            systemImage: "tray",
                            description: Text("入力画面の保存ボタンで残すと、ここでまとめて集計できます。")
                        )
                        .padding(.top, 30)
                    } else if data.reports.isEmpty {
                        ContentUnavailableView(
                            "この条件に合う対局がありません",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("期間や打ち方を変えてみてください。")
                        )
                        .padding(.top, 30)
                    } else {
                        summary(data)
                        heading("ハイライト")
                        highlights(data)
                        heading("成績")
                        playerDetailsButton(data)
                        table(data)
                        heading("着順の割合")
                        rankChart(data)
                        heading("推移（局ごとの累計）")
                        chart(data)
                        legend(data)
                        // 最近の記録は一番下（本人の指示）。1回ぶんの表をそのまま見せる
                        if latestGame(data) != nil {
                            heading("最近の記録")
                            latestRecord(data)
                        }
                        Text("・「個人成績の詳細を見る」から、1人ずつ詳しい成績と相性が見られます\n・着順は局ごとに付けています。同点は表の左の人が上です")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.inkDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
            }
            // 数字も漢字も同じ書体にそろえる。場所ごとに書体を指定すると混ざる
            .fontDesign(.rounded)
            .background(Palette.bg)
            .navigationTitle(directory.map { "\($0.name)の集計" } ?? "全記録のビュー")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: PlayerPage.self) { page in
                PlayerPagerView(
                    names: data.ranked.map(\.name), games: data.selected,
                    decimalMode: data.decimalMode, seats: data.seats,
                    colors: Dictionary(uniqueKeysWithValues: data.ranked.map { ($0.name, data.color($0.name)) }),
                    start: page.start
                )
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        showImages = true
                    } label: {
                        Label("画像で送る", systemImage: "photo.on.rectangle.angled")
                    }
                    .disabled(data.reports.isEmpty)
                    .accessibilityIdentifier("makeImages")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .sheet(isPresented: $showImages) {
                ShareImagesSheet(pages: sharePages(data), colorScheme: colorScheme)
            }
        }
        .onAppear {
            // いちばん多く打っている打ち方を最初に選ぶ。混ざった数字を最初に見せない
            if style == nil || !styles.contains(style ?? 0) {
                style = games.map(\.style).mostCommon() ?? styles.first
            }
        }
    }

    // MARK: - 画像で送る

    /// 画像で送る4枚。**画面と同じ部品をそのまま並べる**（普通にスクリーンショットを撮ったのと同じ見た目）。
    /// 並びは本人の指示：①最近の記録（共有するとき一番知りたい）②累計の表 ③ハイライト ④着順の割合と推移。
    /// 題名などの共通の見出しは載せない。個人成績への入口のボタンは画像には要らない
    private func sharePages(_ data: Computed) -> [ShareImagesSheet.Page] {
        var pages: [ShareImagesSheet.Page] = []
        if latestGame(data) != nil {
            pages.append(.init(caption: "最近の記録", content: AnyView(
                VStack(alignment: .leading, spacing: 12) {
                    heading("最近の記録")
                    latestRecord(data)
                }
            )))
        }
        pages.append(.init(caption: "累計", content: AnyView(
            VStack(alignment: .leading, spacing: 12) {
                heading("成績")
                table(data)
            }
        )))
        pages.append(.init(caption: "ハイライト", content: AnyView(
            VStack(alignment: .leading, spacing: 12) {
                heading("ハイライト")
                highlights(data)
            }
        )))
        pages.append(.init(caption: "着順と推移", content: AnyView(
            VStack(alignment: .leading, spacing: 12) {
                heading("着順の割合")
                rankChart(data)
                heading("推移（局ごとの累計）")
                chart(data)
                legend(data)
            }
        )))
        return pages
    }

    // MARK: - 絞り込み

    private func filters(styles: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("期間", selection: $period) {
                ForEach(Period.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("periodPicker")

            // 三麻と四麻の両方があるときだけ出す。混ぜた「すべて」は着順の分母が変わるので置かない
            if styles.count > 1 {
                Picker("打ち方", selection: $style) {
                    ForEach(styles, id: \.self) { value in
                        Text(StatsFormat.styleLabel(value)).tag(Int?.some(value))
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("stylePicker")
            }

            if hasMixedDecimalModes {
                Picker("表示モード", selection: $decimalMode) {
                    Text("整数").tag(Bool?.some(false))
                    Text("小数").tag(Bool?.some(true))
                    Text("すべて").tag(Bool?.none)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("decimalModePicker")

                if decimalMode == nil {
                    warning("小数モードの記録と整数モードの記録が混ざっています。合計が10倍ズレて見えます。")
                }
            }
        }
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 11))
            .foregroundStyle(Palette.negative)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func summary(_ data: Computed) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(data.selected.count) 対局 ・ \(data.roundCount) 局 ・ \(StatsFormat.styleLabel(style))")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.accent)
            if data.unknownDateGames > 0 {
                Text("日付未記入の \(data.unknownDateGames) 対局は「全期間」でだけ数えます")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.inkDim)
            }
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .kerning(0.5)
            .foregroundStyle(Palette.inkDim)
    }

    // MARK: - ハイライト

    private struct Highlight: Identifiable {
        let id: String
        /// 項目ならではの絵。主の記号と、添える小さな記号
        let symbol: String
        let accent: String?
        let name: String
        let value: String
        /// 名前の下に添える一言（その記録を出した日など）
        let note: String?
        let color: Color
    }

    /// 率で並べるハイライトの対象にする最低の局数。数局だけの人が100%で並ばないように
    private static let minimumRounds = 5

    private func highlightItems(_ data: Computed) -> [Highlight] {
        let reports = data.reports
        let decimal = data.decimalMode
        var items: [Highlight] = []
        func add(_ title: String, _ symbol: String, accent: String? = nil,
                 _ name: String, _ value: String, note: String? = nil) {
            items.append(Highlight(id: title, symbol: symbol, accent: accent, name: name, value: value,
                                   note: note, color: data.color(name)))
        }

        // 率で並べるものは、数局しか打っていない人が100%で並ばないよう5局以上に絞る
        let regulars = reports.filter { $0.rounds >= Self.minimumRounds }

        // 1段目：トップ率・平均着順・連続トップ（本人の指示の並び）
        // 回数ではなく率にする。回数だと打った数の多い人が有利になる。何回中何回かを添える
        if let r = regulars.max(by: { ($0.topRate ?? 0) < ($1.topRate ?? 0) }) {
            add("トップ率", "crown.fill", accent: "sparkles", r.name, StatsFormat.percent(r.topRate),
                note: "\(r.rounds)回中 \(r.count(ofRank: 1))回")
        }
        if let r = regulars.min(by: { ($0.averageRank ?? .infinity) < ($1.averageRank ?? .infinity) }) {
            add("平均着順", "medal.fill", accent: "star.fill", r.name, StatsFormat.rank(r.averageRank),
                note: "参加\(r.rounds)回の平均")
        }
        if let r = reports.max(by: { $0.longestTopStreak < $1.longestTopStreak }) {
            add("連続トップ", "flame.fill", accent: "flame.fill", r.name, "\(r.longestTopStreak)連続",
                note: StatsFormat.day(r.longestTopStreakDate))
        }

        // 2段目：ラス回避率・最高の日・絶好調
        // 率だけだと何回中なのか分からない。分母（打った局数）と、ラスになった回数を添える
        if let r = regulars.max(by: { ($0.lastAvoidRate ?? 0) < ($1.lastAvoidRate ?? 0) }) {
            add("ラス回避率", "checkmark.shield.fill", r.name, StatsFormat.percent(r.lastAvoidRate),
                note: "\(r.rounds)局中 ラス\(r.lastCount)回")
        }
        // 1回の記録（その日）の合計がいちばん多かった人。「対局」だと1局と紛らわしいので「最高の日」
        if let r = reports.max(by: { ($0.bestGame ?? .min) < ($1.bestGame ?? .min) }), let best = r.bestGame {
            add("最高の日", "trophy.fill", accent: "sparkles", r.name, StatsFormat.signed(best, decimal),
                note: StatsFormat.day(r.bestGameDate))
        }
        // 卓全体の直近で切る。しばらく来ていない人の昔の好成績を「今」として出さない
        let hot = Report.recentWindow(games: data.selected)
            .filter { $0.rounds >= Self.minimumRounds }
            .max { $0.averageScore < $1.averageScore }
        if let hot {
            add("絶好調", "bolt.fill", accent: "bolt.fill", hot.name, StatsFormat.average(hot.averageScore, decimal),
                note: "直近\(min(Report.hotWindow, data.roundCount))局の1局平均")
        }

        // 3段目：最多参加・最高の1局・痛恨の1局（1局の最高と最低を並べる）
        // 「皆勤賞」にしない。60回中55回でも1番なら出るので、皆勤とは限らない
        if let r = reports.max(by: { $0.rounds < $1.rounds }) {
            add("最多参加", "calendar.badge.checkmark", r.name, "\(r.rounds)回",
                note: "全\(data.roundCount)局中の参加回数")
        }
        if let r = reports.max(by: { ($0.bestRound ?? .min) < ($1.bestRound ?? .min) }), let best = r.bestRound {
            add("最高の1局", "star.fill", accent: "sparkle", r.name, StatsFormat.signed(best, decimal),
                note: StatsFormat.day(r.bestRoundDate))
        }
        if let r = reports.min(by: { ($0.worstRound ?? .max) < ($1.worstRound ?? .max) }), let worst = r.worstRound {
            add("痛恨の1局", "cloud.bolt.rain.fill", r.name, StatsFormat.signed(worst, decimal),
                note: StatsFormat.day(r.worstRoundDate))
        }
        return items
    }

    /// 3列×3段。9つを1画面の上半分で見渡せるようにする
    ///
    /// 遅延の格子（Lazy の付く格子）にしない。画像で送るとき `ImageRenderer` は遅延の格子を描かずに
    /// 空にすることがある。9枠しかないので、普通の Grid で困らない
    private func highlights(_ data: Computed) -> some View {
        let items = highlightItems(data)
        let rows = stride(from: 0, to: items.count, by: 3).map { Array(items[$0..<min($0 + 3, items.count)]) }
        return Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(rows.indices, id: \.self) { index in
                GridRow {
                    ForEach(rows[index]) { item in
                        HighlightCard(title: item.id, symbol: item.symbol, accent: item.accent, name: item.name,
                                      value: item.value, note: item.note, color: item.color)
                    }
                    // 3つに満たない段も、枠の幅は3等分のままにする
                    ForEach(0..<(3 - rows[index].count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
            }
        }
    }

    /// 塗りつぶした面の上の文字。人の色はどれも明るめなので、白より濃い色の方が読める
    private static let onColorInk = HighlightCard.darkInk

    // MARK: - 成績表

    /// 列ごとに、いちばん長い値（「+37.6」「100」など）が14ptで収まる幅を決め打ちにする。
    /// **等分にしない。** 等分だと長い値のマスだけ字が縮み、同じ行で字の大きさがそろわない
    private static let columns: [(title: String, width: CGFloat)] = [
        ("局", 28), ("合計", 48), ("平均", 42), ("平着", 38), ("トップ率", 42), ("連対率", 40), ("ラス率", 40),
    ]

    /// 名前の欄の**上限**。いちばん長い名前が入る幅。余った幅を名前に回すと、短い名前のとき局数との間が空きすぎる。
    /// **上限であって固定ではない。** 固定にすると長い名前（「プレイヤー2」など）で表が画面より広くなり、
    /// 集計の画面ごと横にはみ出して左右が切れた。足りないときは名前の欄だけが縮み、名前の字を縮めて入れる
    private func nameWidth(_ data: Computed) -> CGFloat {
        let longest = data.ranked.map { $0.name.count }.max() ?? 2
        return min(90, max(46, CGFloat(longest) * 14 + 14))
    }

    private static let nameMinWidth: CGFloat = 40

    /// **最近の記録。** 対局日がいちばん新しい記録を、入力の表と同じ情報（局ごとの点数と合計）で見せる。
    /// 集計の一番下に置き、画像で送るときは1枚目にする（共有するとき一番知りたいのがこれ。本人の指示）
    @ViewBuilder
    private func latestRecord(_ data: Computed) -> some View {
        if let game = latestGame(data) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(StatsFormat.day(game.playedAt) ?? "")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.ink)
                    Text("\(Report.roundCount(games: [game]))局")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.inkDim)
                    Spacer(minLength: 0)
                }
                // 画像にするので横に送らず、画面の幅に収める
                RoundTableView(session: game.session, fitsWidth: true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("latestRecord")
        }
    }

    /// 対局日がいちばん新しい記録。`selected` は対局日の古い順で、同じ日付どうしは保存の新しい順を保っている
    private func latestGame(_ data: Computed) -> GameForStats? {
        guard let last = data.selected.last else { return nil }
        return data.selected.first { $0.playedAt == last.playedAt }
    }

    /// 個人成績の入口。**緑の線だけの枠に、文字と矢印。** 10種類の試作から本人が選んだ形（2026-09-13。「線だけ」）。
    /// 押すと1人目から横に送る個人成績が開く。表の行からは開かない（入口はここ1つ）
    private func playerDetailsButton(_ data: Computed) -> some View {
        NavigationLink(value: PlayerPage(start: data.ranked.first?.name ?? "")) {
            HStack(spacing: 8) {
                Text("個人成績の詳細を見る")
                    .font(.system(size: 15, weight: .bold))
                Spacer(minLength: 4)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(Palette.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.accent, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(data.ranked.isEmpty)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("個人成績の詳細を見る")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("openPlayerDetails")
    }

    private func table(_ data: Computed) -> some View {
        let width = nameWidth(data)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                // 余った幅は左右に半分ずつ。「＞」を外して右だけ空いたので、名前の左にも同じだけ空ける（本人の指示）
                Spacer(minLength: 0)
                // 名前の欄は行と同じ組み方にしてそろえる。左右の余白より先に名前へ幅を回す
                Color.clear.frame(minWidth: Self.nameMinWidth, maxWidth: width, maxHeight: 1)
                    .layoutPriority(1)
                ForEach(Self.columns, id: \.title) { column in
                    Text(column.title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.inkDim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: column.width)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 8)

            ForEach(data.ranked) { report in
                // 行からは開かない。入口は上の「個人成績の詳細を見る」だけ（本人の指示）
                row(report, data, nameWidth: width)
                    .accessibilityIdentifier("statsRow-\(report.name)")
                if report.id != data.ranked.last?.id {
                    Divider()
                }
            }
        }
        .padding(12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line))
    }

    private func row(_ report: PlayerReport, _ data: Computed, nameWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Circle().fill(data.color(report.name)).frame(width: 7, height: 7)
                // 長い名前は「…」で切らずに縮めて全部見せる。誰の行か分からなくなるので
                Text(report.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(minWidth: Self.nameMinWidth, maxWidth: nameWidth, alignment: .leading)
            .layoutPriority(1)

            // 率のマスは％を付けない。見出しに「率」と書いてあるので、数字だけの方が詰まって見えない
            let values: [(String, Bool)] = [
                ("\(report.rounds)", false),
                (StatsFormat.signed(report.total, data.decimalMode), report.total < 0),
                (StatsFormat.average(report.averageScore, data.decimalMode), (report.averageScore ?? 0) < 0),
                (StatsFormat.rank(report.averageRank), false),
                (StatsFormat.rateNumber(report.topRate), false),
                (StatsFormat.rateNumber(report.rentaiRate), false),
                (StatsFormat.rateNumber(report.lastRate), false),
            ]
            ForEach(Array(zip(Self.columns, values).enumerated()), id: \.offset) { _, pair in
                cell(pair.1.0, negative: pair.1.1, width: pair.0.width)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        // マス単位で読ませると数字だけが並んで意味が取れない。行ごとにまとめる
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(report, data))
    }

    private func cell(_ text: String, negative: Bool, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(negative ? Palette.negative : Palette.ink)
            .lineLimit(1)
            // 決め打ちの幅で収まる前提。桁の多い点数のときだけの保険
            .minimumScaleFactor(0.75)
            .frame(width: width)
    }

    private func spoken(_ report: PlayerReport, _ data: Computed) -> String {
        var parts = [report.name, "\(report.rounds)局",
                     "合計 \(StatsFormat.signed(report.total, data.decimalMode))"]
        if let rank = report.averageRank { parts.append("平均着順 \(String(format: "%.2f", rank))") }
        parts.append("トップ率 \(StatsFormat.percent(report.topRate))")
        parts.append("ラス率 \(StatsFormat.percent(report.lastRate))")
        return parts.joined(separator: "、")
    }

    // MARK: - 着順の割合

    private struct RankShare: Identifiable {
        let id: String
        let name: String
        let rank: String
        let rate: Double
    }

    private func rankShares(_ order: [PlayerReport], seats: Int) -> [RankShare] {
        order.flatMap { report in
            (1...seats).map { rank in
                RankShare(id: "\(report.name)-\(rank)", name: report.name, rank: "\(rank)位",
                          rate: report.rounds > 0 ? Double(report.count(ofRank: rank)) / Double(report.rounds) : 0)
            }
        }
    }

    /// 1局の平均点の高い順。合計だと、打った局数の多い人が上に来てしまう
    private func byAverageScore(_ reports: [PlayerReport]) -> [PlayerReport] {
        reports.enumerated()
            .sorted { lhs, rhs in
                let l = lhs.element.averageScore ?? -.infinity
                let r = rhs.element.averageScore ?? -.infinity
                return l != r ? l > r : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private func rankChart(_ data: Computed) -> some View {
        let order = byAverageScore(data.reports)
        let shares = rankShares(order, seats: data.seats)
        let names = order.map(\.name)
        let ranks = (1...data.seats).map { "\($0)位" }
        let colors = (1...data.seats).map { StatsFormat.rankColor($0, seats: data.seats) }
        return Chart(shares) { share in
            BarMark(x: .value("割合", share.rate), y: .value("名前", share.name), height: .fixed(30))
                .foregroundStyle(by: .value("着順", share.rank))
                .annotation(position: .overlay) {
                    // 細い区間に数字を入れると潰れて読めない。1割以上の区間だけに書く
                    if share.rate >= 0.1 {
                        Text("\(Int((share.rate * 100).rounded()))%")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Self.onColorInk)
                    }
                }
        }
        .chartForegroundStyleScale(domain: ranks, range: colors)
        .chartYScale(domain: names)
        .chartXScale(domain: 0...1)
        // 割合は棒の中に書くので、下の目盛りは要らない
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let name = value.as(String.self) {
                        Text(name)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.ink)
                    }
                }
            }
        }
        .chartLegend(position: .top, alignment: .leading, spacing: 10)
        .frame(height: CGFloat(max(2, names.count)) * 44 + 36)
    }

    // MARK: - 推移

    fileprivate struct Series: Identifiable {
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

    /// 目盛りの位置。局数は整数なので、小数のラベルが出ないよう自分で並べる
    private func xTicks(_ data: Computed) -> [Int] {
        let count = data.series.first?.points.count ?? 0
        guard count > 0 else { return [0] }
        let step = Swift.max(1, count / 5)
        // 右端に寄りすぎた目盛りは数字が画面の外に切れる（「50」が「5」に見えた）。半目盛りより寄ったら出さない
        return stride(from: step, through: count, by: step).filter { count - $0 >= Swift.max(1, step / 2) || $0 == step }
    }

    private func chart(_ data: Computed) -> some View {
        Chart {
            ForEach(data.series) { line in
                ForEach(line.plotted) { point in
                    // series: を渡さないと、全員の点が1本の線として繋がってしまう
                    LineMark(
                        x: .value("局", point.index),
                        y: .value("累計", point.value),
                        series: .value("名前", line.id)
                    )
                    .foregroundStyle(line.color)
                    .opacity(opacity(for: line.id))
                }
            }
        }
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: xTicks(data)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let n = value.as(Int.self) { Text("\(n)") }
                }
            }
        }
        .frame(height: 220)
    }

    private func legend(_ data: Computed) -> some View {
        // 凡例をタップすると1人だけ強調する
        FlowRow(spacing: 8) {
            ForEach(data.series) { line in
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

// MARK: - ハイライトの枠

/// ハイライト1枠。**暗い地に、その人の色で光る四角の枠。項目ならではの絵を大きく透かす。**
///
/// 試作を2回見比べて本人が選んだ形（2026-09-13。2回目の④「コーナー金具」）を元に、
/// 四隅だけだった枠を**切れ目のない四角**にした（本人の指示）。
/// 好評だった点：枠がある・派手に光る・項目ごとの絵がある。
/// 地はライトモードでも暗いまま。明るい地だと枠が光って見えない
private struct HighlightCard: View {
    let title: String
    let symbol: String
    let accent: String?
    let name: String
    let value: String
    let note: String?
    let color: Color

    static let height: CGFloat = 124
    /// 塗りつぶした面の上の濃い文字（着順の割合のグラフでも使う）
    static let darkInk = Color(red: 0.06, green: 0.08, blue: 0.06)
    static let night = Color(red: 0.05, green: 0.06, blue: 0.07)

    var body: some View {
        // 見出しと名前は、真ん中の数字（26pt）より少し小さいくらいまで大きくする（本人の指示）。
        // 見出しは「ラス回避率」など5文字あるので、枠からはみ出す手前で字を縮める
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text(value)
                .font(.system(size: 26, weight: .black))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(name)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            // 日付の無い枠も同じ段組みにして、値と名前の位置をそろえる
            Text(note ?? "–")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .opacity(note == nil ? 0 : 1)
                .accessibilityHidden(note == nil)
        }
        // 横の余白を詰めて、大きくした見出しと名前に幅を回す
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background {
            ZStack {
                Self.night
                Illustration(symbol: symbol, accent: accent, size: 60, color: color.opacity(0.16))
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color, lineWidth: 2.5))
        .shadow(color: color.opacity(0.5), radius: 6)
        // 読み上げは見出しから始める（絵は読ませない。UIテストもこの順で探す）
        .accessibilityElement(children: .combine)
    }
}

/// 項目ならではの絵。主の記号に、小さな記号を右上へ添える（王冠にきらめき、炎に炎など）
private struct Illustration: View {
    let symbol: String
    let accent: String?
    let size: CGFloat
    let color: Color

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .black))
            if let accent {
                Image(systemName: accent)
                    .font(.system(size: size * 0.4, weight: .black))
                    .offset(x: size * 0.3, y: -size * 0.2)
            }
        }
        .foregroundStyle(color)
        .accessibilityHidden(true)
    }
}

