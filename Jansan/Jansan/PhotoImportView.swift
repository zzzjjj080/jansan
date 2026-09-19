import SwiftUI
import SwiftData
import PhotosUI
import JansanCore

/// スクリーンショットや紙のスコア表から、記録を取り込む。
///
/// **道は2つだけ**（端末の中だけで読む方式は、実用にならなかったので外した。本人の指示）。
/// 1. 設定でAPIキーを入れておき、この画面から「AIに読ませる」
/// 2. お願い文をコピーして、自分で ChatGPT や Claude に写真ごと渡し、返ってきた表を貼る
///
/// どちらでも、**取り込む前に文字で見せて直せる**ようにしてある
struct PhotoImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\Directory.sortOrder), SortDescriptor(\Directory.createdAt)])
    private var directories: [Directory]
    @AppStorage("currentDirectory") private var currentDirectoryID = Directory.defaultUID.uuidString

    @State private var settings = AISettings.shared
    @State private var target: UUID?
    @State private var photo: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var showCamera = false
    @State private var askingAI = false
    @State private var text = ""
    @State private var games: [CSVImportedGame] = []
    @State private var duplicate: [Bool] = []
    @State private var failure: String?
    @State private var addedCount = 0
    @State private var done = false
    @State private var didCopyPrompt = false
    @State private var reads = 0
    @State private var commits = 0

    /// 入れられるのは自分のフォルダだけ。受け取ったものは書き換えられない
    private var choices: [Directory] {
        directories.filter { $0.isEditable && !$0.isAutoBackup }
    }

    private var directory: Directory? {
        choices.first { $0.uid == target }
            ?? choices.first { $0.uid.uuidString == currentDirectoryID }
            ?? choices.first
    }

    private var newGames: [CSVImportedGame] {
        zip(games, duplicate).filter { !$0.1 }.map(\.0)
    }

    var body: some View {
        NavigationStack {
            Form {
                photoSection
                if settings.hasKey { aiReadSection } else { noKeySection }
                promptSection
                textSection
                if !games.isEmpty { planSection }
            }
            .navigationTitle("写真から取り込む")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("やめる") { dismiss() }
                }
            }
            .sensoryFeedback(.selection, trigger: reads)
            .sensoryFeedback(.success, trigger: commits)
            .alert("取り込めませんでした", isPresented: Binding(get: { failure != nil },
                                                          set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) { failure = nil }
            } message: {
                Text(failure ?? "")
            }
            .alert("取り込みました", isPresented: $done) {
                Button("OK") { dismiss() }
            } message: {
                Text("\(addedCount) 件を「\(directory?.name ?? "")」に追加しました。日付は未記入です。")
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task { await load(item) }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { picked in image = picked }
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - 写真を選ぶ

    private var photoSection: some View {
        Section {
            Picker("入れる先", selection: Binding(get: { directory?.uid ?? Directory.defaultUID },
                                               set: { target = $0 })) {
                ForEach(choices) { dir in
                    Text(dir.name).tag(dir.uid)
                }
            }
            .accessibilityIdentifier("photoImportDirectory")

            // その場で撮る。**撮った写真は写真アプリにも残す**ので、あとから見返せる
            if CameraPicker.isAvailable {
                Button {
                    showCamera = true
                } label: {
                    Label("カメラで撮る", systemImage: "camera")
                }
                .accessibilityIdentifier("takePhoto")
            }

            PhotosPicker(selection: $photo, matching: .images, photoLibrary: .shared()) {
                Label(image == nil ? "写真やスクショを選ぶ" : "別の写真にする", systemImage: "photo.on.rectangle")
            }
            .accessibilityIdentifier("pickPhoto")

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
            }
        } header: {
            Text("紙のスコア表・他のアプリの画面")
        } footer: {
            Text("カメラで撮った写真は、写真アプリにも残ります。")
        }
    }

    // MARK: - AIに読ませる（鍵がある人）

    private var aiReadSection: some View {
        Section {
            Button {
                askAI()
            } label: {
                HStack {
                    Label(askingAI ? "読んでいます…" : "AIに読ませる", systemImage: "wand.and.stars")
                    if askingAI {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(image == nil || askingAI)
            .accessibilityIdentifier("askAI")
        } header: {
            Text("AIで読み取る")
        } footer: {
            Text("選んだ写真を\(settings.provider.name)へ送り、点数の表にしてもらいます。送るのはこのボタンを押したときだけです。料金はご自身の契約にかかります。")
        }
    }

    /// 鍵が無い人への案内。**押せないボタンを並べない**で、やることだけ書く
    private var noKeySection: some View {
        Section {
            Label("設定の「AIで読み取る」でAPIキーを入れると、この画面から直接読み取れます",
                  systemImage: "key")
                .font(.footnote)
                .foregroundStyle(Palette.inkDim)
                .accessibilityIdentifier("aiKeyHint")
        } header: {
            Text("AIで読み取る")
        }
    }

    // MARK: - 自分でAIに渡す

    private var promptSection: some View {
        Section {
            Button {
                UIPasteboard.general.string = CSVImport.aiPrompt
                didCopyPrompt = true
                Task {
                    try? await Task.sleep(for: .seconds(1.8))
                    didCopyPrompt = false
                }
            } label: {
                Label(didCopyPrompt ? "コピーしました" : "AIへのお願い文をコピー",
                      systemImage: didCopyPrompt ? "checkmark.circle.fill" : "doc.on.doc")
            }
            .accessibilityIdentifier("copyAIPromptFromPhoto")
        } header: {
            Text("自分でAIに渡す")
        } footer: {
            Text("APIキーを使わない方法です。ChatGPT や Claude のアプリに写真とこのお願い文を渡し、返ってきた表を下の欄に貼ってください。")
        }
    }

    // MARK: - 取り込む表

    private var textSection: some View {
        Section {
            TextEditor(text: $text)
                .frame(minHeight: 130)
                .font(.system(size: 12, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("photoReadField")
                .onChange(of: text) {
                    games = []
                    duplicate = []
                }

            HStack {
                PasteButton(payloadType: String.self) { strings in
                    Task { @MainActor in text = strings.joined(separator: "\n") }
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)

                Spacer()

                Button {
                    preview()
                } label: {
                    Label("中身を確かめる", systemImage: "eye")
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("previewPhoto")
            }
            .buttonStyle(.borderless)
        } header: {
            Text("取り込む表")
        } footer: {
            Text("1行目が名前、そのあとが1局ずつの点数です。読み違いはここで直せます。お休みの人は空欄にします。")
        }
    }

    // MARK: - 取り込む内容

    private var planSection: some View {
        Section {
            ForEach(Array(games.enumerated()), id: \.offset) { index, game in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(game.session.players.count)人・\(game.session.playedRoundCount)局")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(duplicate[index] ? Palette.inkDim : Palette.ink)
                    Text(summary(game))
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.inkDim)
                    if duplicate[index] {
                        Text("同じ内容がすでにあるので飛ばします")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.negative)
                    }
                }
            }

            Button {
                commit()
            } label: {
                Label("\(newGames.count) 件を取り込む", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .disabled(newGames.isEmpty)
            .accessibilityIdentifier("commitPhoto")
        } header: {
            Text("取り込む内容")
        }
    }

    // MARK: - 処理

    private func load(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let picked = UIImage(data: data) else {
            failure = "写真を読み込めませんでした。"
            return
        }
        image = picked
    }

    /// 写真を AI に送って表にしてもらう。**押したときだけ送る**
    private func askAI() {
        guard let image, let reader = settings.reader else { return }
        askingAI = true
        Task {
            do {
                text = try await reader.readCSV(from: image)
                games = []
                duplicate = []
                reads += 1
            } catch {
                failure = error.localizedDescription
            }
            askingAI = false
        }
    }

    private func preview() {
        guard let directory else { return }
        do {
            let parsed = try CSVImport.parse(text)
            let existing = Set(DirectoryStore.games(of: directory, in: context).compactMap { record in
                (try? record.snapshot()).map { CSVImport.fingerprint(of: $0.session) }
            })
            duplicate = CSVImport.duplicates(parsed, existing: existing)
            games = parsed
        } catch let error as CSVImportError {
            games = []
            failure = CSVImportMessage.text(for: error)
        } catch {
            games = []
            failure = "読み取れない形式でした。"
        }
    }

    private func commit() {
        guard let directory else { return }
        addedCount = ImportCommit.insert(newGames, into: directory, in: context)
        commits += 1
        games = []
        duplicate = []
        text = ""
        image = nil
        photo = nil
        done = true
    }

    private func summary(_ game: CSVImportedGame) -> String {
        zip(game.session.players, game.session.playerStats().map(\.total))
            .map { "\($0) \(ScoreFormatter.signedString($1, decimalMode: game.session.decimalMode))" }
            .joined(separator: " / ")
    }
}
