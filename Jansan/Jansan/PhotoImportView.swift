import SwiftUI
import SwiftData
import JansanCore

/// 写真やスクリーンショットの点数を、AI に表へ直してもらって取り込む。
///
/// **アプリ自身は写真を読まない**（端末の中で読む方式も、APIキーで送る方式も、使いものにならなかったので外した）。
/// やることは「お願い文をコピーして、自分のAIアプリに写真と一緒に渡し、返ってきた表を貼る」だけ。
/// そのぶん、**手順を画面に書いて、押す所を大きくする**
struct PhotoImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\Directory.sortOrder), SortDescriptor(\Directory.createdAt)])
    private var directories: [Directory]
    @AppStorage("currentDirectory") private var currentDirectoryID = Directory.defaultUID.uuidString

    @State private var target: UUID?
    @State private var text = ""
    @State private var games: [CSVImportedGame] = []
    @State private var duplicate: [Bool] = []
    @State private var failure: String?
    @State private var addedCount = 0
    @State private var done = false
    @State private var didCopyPrompt = false
    @State private var copies = 0
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
                howToSection
                copySection
                pasteSection
                if !games.isEmpty { planSection }
            }
            .navigationTitle("写真から取り込む")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("やめる") { dismiss() }
                }
            }
            .sensoryFeedback(.success, trigger: copies)
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
        }
    }

    // MARK: - やり方

    private var howToSection: some View {
        Section {
            step(1, "スコア表を写真に撮る", "紙でも、他のアプリの画面のスクショでも構いません")
            step(2, "下の「お願い文をコピー」を押す", "AIに渡す文章がコピーされます")
            step(3, "ChatGPT や Claude のアプリを開く", "写真を貼り、コピーした文も貼って送ります")
            step(4, "返ってきた表をコピーする", "「中村,五十嵐,…」で始まる表です")
            step(5, "ここに戻って貼り、取り込む", "貼ったあと「中身を確かめる」→「取り込む」")
        } header: {
            Text("やり方")
        } footer: {
            Text("アプリ自身は写真を読みません。読み取りはお使いのAIアプリに任せ、その結果を取り込みます。")
        }
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Palette.accentInk)
                .frame(width: 26, height: 26)
                .background(Palette.accent, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.inkDim)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    // MARK: - ① コピー

    private var copySection: some View {
        Section {
            Button {
                UIPasteboard.general.string = CSVImport.aiPrompt
                didCopyPrompt = true
                copies += 1
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    didCopyPrompt = false
                }
            } label: {
                bigLabel(didCopyPrompt ? "コピーしました" : "AIへのお願い文をコピー",
                         systemImage: didCopyPrompt ? "checkmark.circle.fill" : "doc.on.doc",
                         filled: true)
            }
            .buttonStyle(.borderless)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .accessibilityIdentifier("copyAIPromptFromPhoto")
        } header: {
            Text("① AIに渡す")
        } footer: {
            Text("写真と一緒に渡すと、この形の表にしてくれます。")
        }
    }

    // MARK: - ② 貼って取り込む

    private var pasteSection: some View {
        Section {
            Picker("入れる先", selection: Binding(get: { directory?.uid ?? Directory.defaultUID },
                                               set: { target = $0 })) {
                ForEach(choices) { dir in
                    Text(dir.name).tag(dir.uid)
                }
            }
            .accessibilityIdentifier("photoImportDirectory")

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

            PasteButton(payloadType: String.self) { strings in
                Task { @MainActor in text = strings.joined(separator: "\n") }
            }
            .labelStyle(.titleAndIcon)
            .buttonBorderShape(.capsule)

            Button {
                preview()
            } label: {
                bigLabel("中身を確かめる", systemImage: "eye", filled: false)
            }
            .buttonStyle(.borderless)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .accessibilityIdentifier("previewPhoto")
        } header: {
            Text("② 返ってきた表を貼る")
        } footer: {
            Text("1行目が名前、そのあとが1局ずつの点数です。ずれていたら直せます。お休みの人は空欄にします。")
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
                bigLabel("\(newGames.count) 件を取り込む", systemImage: "square.and.arrow.down", filled: true)
            }
            .buttonStyle(.borderless)
            .disabled(newGames.isEmpty)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .accessibilityIdentifier("commitPhoto")
        } header: {
            Text("③ 取り込む内容")
        }
    }

    /// 押す所は大きく。指で押しやすい高さにして、何をする所かを言葉で出す
    private func bigLabel(_ title: String, systemImage: String, filled: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(filled ? Palette.accentInk : Palette.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(filled ? Palette.accent : Palette.accent.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
    }

    // MARK: - 処理

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
        done = true
    }

    private func summary(_ game: CSVImportedGame) -> String {
        zip(game.session.players, game.session.playerStats().map(\.total))
            .map { "\($0) \(ScoreFormatter.signedString($1, decimalMode: game.session.decimalMode))" }
            .joined(separator: " / ")
    }
}
