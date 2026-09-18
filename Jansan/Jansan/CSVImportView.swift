import SwiftUI
import SwiftData
import JansanCore

/// 書き出し（CSV）を貼って、このディレクトリに記録として足す。
///
/// **CSV には日付もメモも無い。** 取り込んだ記録は「日付未記入」で入り、あとから記録の編集で入れる。
/// 同じ表を二度貼っても二重には入らない（中身が同じものは飛ばす）。
/// 日付・メモごと丸ごと戻したいときは、設定の「バックアップ」を使う
struct CSVImportView: View {
    let directory: Directory
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var pasted = ""
    @State private var games: [CSVImportedGame] = []
    @State private var duplicate: [Bool] = []
    @State private var failure: String?
    @State private var addedCount = 0
    @State private var done = false
    /// 触覚の合図。値が変わるたびに鳴る
    @State private var previews = 0
    @State private var commits = 0
    @State private var showPrompt = false
    @State private var didCopyPrompt = false
    @State private var promptCopies = 0
    @FocusState private var editing: Bool

    private var newGames: [CSVImportedGame] {
        zip(games, duplicate).filter { !$0.1 }.map(\.0)
    }

    var body: some View {
        NavigationStack {
            Form {
                pasteSection
                aiSection
                if !games.isEmpty { planSection }
            }
            .navigationTitle("CSVを取り込む")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("やめる") { dismiss() }
                }
            }
            .sensoryFeedback(.selection, trigger: previews)
            .sensoryFeedback(.success, trigger: commits)
            .sensoryFeedback(.success, trigger: promptCopies)
            .alert("取り込めませんでした", isPresented: Binding(get: { failure != nil },
                                                          set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) { failure = nil }
            } message: {
                Text(failure ?? "")
            }
            .alert("取り込みました", isPresented: $done) {
                Button("OK") { dismiss() }
            } message: {
                Text("\(addedCount) 件を「\(directory.name)」に追加しました。日付は未記入です。")
            }
        }
    }

    // MARK: - 貼り付け

    private var pasteSection: some View {
        Section {
            TextEditor(text: $pasted)
                .frame(minHeight: 150)
                .font(.system(size: 12, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($editing)
                .accessibilityIdentifier("csvPasteField")
                // 貼り直したら、前に確かめた内容は捨てる。古い内容のまま取り込ませない
                .onChange(of: pasted) {
                    games = []
                    duplicate = []
                }

            HStack {
                PasteButton(payloadType: String.self) { strings in
                    Task { @MainActor in pasted = strings.joined(separator: "\n") }
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)

                Spacer()

                Button {
                    preview()
                } label: {
                    Label("中身を確かめる", systemImage: "eye")
                }
                .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("previewCSV")
            }
            .buttonStyle(.borderless)
        } header: {
            Text("「\(directory.name)」に取り込む")
        } footer: {
            Text("・書き出し（CSV）をそのまま貼れます\n・表をいくつか続けて貼ると、表ごとに1件になります\n・日付は「日付未記入」で入ります。あとから記録の編集で入れられます")
        }
    }

    // MARK: - AI に変換してもらう

    /// 写真・紙のスコア表・他のアプリの画面は、そのままでは読めない。
    /// AI にこの形へ書き換えてもらう前提で、お願い文を渡せるようにしておく。
    /// **普段は畳んでおく。** 貼る欄と取り込むボタンを遠ざけないため
    private var aiSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showPrompt) {
                Text(CSVImport.aiPrompt)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.inkDim)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("aiPromptText")

                Button {
                    UIPasteboard.general.string = CSVImport.aiPrompt
                    didCopyPrompt = true
                    promptCopies += 1
                    Task {
                        try? await Task.sleep(for: .seconds(1.8))
                        didCopyPrompt = false
                    }
                } label: {
                    Label(didCopyPrompt ? "コピーしました" : "お願い文をコピー",
                          systemImage: didCopyPrompt ? "checkmark.circle.fill" : "doc.on.doc")
                }
                .accessibilityIdentifier("copyAIPrompt")
            } label: {
                Label("写真や他のアプリから入れる", systemImage: "sparkles")
            }
        } footer: {
            Text("・成績の写真や他のアプリの画面を、ChatGPT や Claude などのAIに渡します\n・このお願い文を一緒に送ると、この形のCSVにしてくれます\n・返ってきたCSVを上の欄に貼ります")
        }
    }

    // MARK: - 取り込む内容

    private var planSection: some View {
        Section {
            ForEach(games.indices, id: \.self) { index in
                gameRow(games[index], isDuplicate: duplicate[index])
            }

            Button {
                commit()
            } label: {
                Label("\(newGames.count) 件を取り込む", systemImage: "square.and.arrow.down")
            }
            .disabled(newGames.isEmpty)
            .accessibilityIdentifier("commitCSV")
        } header: {
            Text("取り込む内容")
        } footer: {
            Text(hasWarnings
                 ? "・注意が出た表も、そのまま取り込めます\n・点数を直すときは、取り込んだ記録を入力に読み込んでから打ち直してください"
                 : "いま入っている記録は消えません。追加だけです。")
        }
    }

    private var hasWarnings: Bool {
        games.contains { !$0.unbalancedRounds.isEmpty || !$0.shortRounds.isEmpty || $0.totalMismatch }
    }

    private func gameRow(_ game: CSVImportedGame, isDuplicate: Bool) -> some View {
        let session = game.session
        let style = session.playersPerRound == 3 ? "三麻" : "四麻"
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("\(session.players.count)人・\(style)・\(session.playedRoundCount)局")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isDuplicate ? Palette.inkDim : Palette.ink)
                if isDuplicate {
                    Text("すでにあるので飛ばす")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.inkDim)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Palette.surface2, in: Capsule())
                }
            }
            Text(zip(session.players, session.totals)
                .map { "\($0) \(ScoreFormatter.signedString($1, decimalMode: session.decimalMode))" }
                .joined(separator: " / "))
                .font(.system(size: 12))
                .foregroundStyle(Palette.inkDim)

            ForEach(warnings(of: game), id: \.self) { text in
                Label(text, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.negative)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func warnings(of game: CSVImportedGame) -> [String] {
        var list: [String] = []
        if !game.unbalancedRounds.isEmpty {
            list.append("合計が0でない局: " + game.unbalancedRounds.map(String.init).joined(separator: ", "))
        }
        if !game.shortRounds.isEmpty {
            list.append("点数が足りない局: " + game.shortRounds.map(String.init).joined(separator: ", "))
        }
        if game.totalMismatch {
            list.append("貼った「合計」の行と、計算した合計が合いません")
        }
        return list
    }

    // MARK: - 動作

    private func preview() {
        editing = false
        do {
            let parsed = try CSVImport.parse(pasted)
            let existing = Set(DirectoryStore.games(of: directory, in: context).compactMap { record in
                (try? record.snapshot()).map { CSVImport.fingerprint(of: $0.session) }
            })
            duplicate = CSVImport.duplicates(parsed, existing: existing)
            games = parsed
            previews += 1
        } catch let error as CSVImportError {
            games = []
            failure = message(for: error)
        } catch {
            games = []
            failure = "読み取れない形式でした。"
        }
    }

    private func commit() {
        addedCount = ImportCommit.insert(newGames, into: directory, in: context)
        commits += 1
        pasted = ""
        done = true
    }

    private func message(for error: CSVImportError) -> String {
        CSVImportMessage.text(for: error)
    }
}
