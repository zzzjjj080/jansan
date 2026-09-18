import SwiftUI
import SwiftData
import PhotosUI
import JansanCore

/// スクリーンショットや紙のスコア表の写真から、記録を取り込む。
///
/// **読み取りは端末の中だけで行う**（Vision）。通信も費用もかからず、写真はどこにも送らない。
/// 読み違いは必ず起きるので、**読んだ結果を文字で見せて直せるようにしてから**取り込む。
/// どうしても読めない写真のために、AIへのお願い文もここから渡せる
struct PhotoImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\Directory.sortOrder), SortDescriptor(\Directory.createdAt)])
    private var directories: [Directory]
    @AppStorage("currentDirectory") private var currentDirectoryID = Directory.defaultUID.uuidString

    @State private var target: UUID?
    @State private var photo: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var reading = false
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
        choices.first { $0.uid == target } ?? choices.first { $0.uid.uuidString == currentDirectoryID } ?? choices.first
    }

    private var newGames: [CSVImportedGame] {
        zip(games, duplicate).filter { !$0.1 }.map(\.0)
    }

    var body: some View {
        NavigationStack {
            Form {
                photoSection
                if !text.isEmpty { readingSection }
                if !games.isEmpty { planSection }
                aiSection
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

            PhotosPicker(selection: $photo, matching: .images, photoLibrary: .shared()) {
                Label(image == nil ? "写真を選ぶ" : "別の写真にする", systemImage: "photo.on.rectangle")
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

            if reading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("読み取っています…").foregroundStyle(Palette.inkDim)
                }
            }
        } header: {
            Text("スクリーンショットや紙の写真")
        } footer: {
            Text("・読み取りはこの端末の中だけで行います。写真はどこにも送りません\n・名前の行と、点数の並びが写っているものを選んでください\n・読み違いは下の欄で直せます")
        }
    }

    // MARK: - 読んだ結果

    private var readingSection: some View {
        Section {
            TextEditor(text: $text)
                .frame(minHeight: 150)
                .font(.system(size: 12, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("photoReadField")
                .onChange(of: text) {
                    games = []
                    duplicate = []
                }

            Button {
                preview()
            } label: {
                Label("中身を確かめる", systemImage: "eye")
            }
            .buttonStyle(.borderless)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("previewPhoto")
        } header: {
            Text("読み取った内容")
        } footer: {
            Text("1行目が名前、そのあとが1局ずつの点数です。ずれていたら直してください。お休みの人は空欄にします。")
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

    // MARK: - AI に頼む

    private var aiSection: some View {
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
                      systemImage: didCopyPrompt ? "checkmark.circle.fill" : "sparkles")
            }
            .accessibilityIdentifier("copyAIPromptFromPhoto")
        } header: {
            Text("うまく読めないとき")
        } footer: {
            Text("手書きや斜めの写真は読み違えます。そのときは ChatGPT や Claude に写真とこのお願い文を渡し、返ってきた内容を上の欄に貼ってください。")
        }
    }

    // MARK: - 処理

    private func load(_ item: PhotosPickerItem) async {
        reading = true
        defer { reading = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let picked = UIImage(data: data) else {
            failure = "写真を読み込めませんでした。"
            return
        }
        image = picked
        games = []
        duplicate = []
        let boxes = await TextInPhoto.read(picked)
        let csv = SheetReader.csv(from: boxes)
        reads += 1
        guard !csv.isEmpty else {
            text = ""
            failure = "文字を読み取れませんでした。明るいところで、表がまっすぐ写るように撮り直すか、AIに読ませてください。"
            return
        }
        text = csv
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
