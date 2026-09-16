import SwiftUI
import SwiftData
import JansanCore

/// 記録のバックアップと取り込み。
///
/// **CSVの取り込みとは別の入口。** CSVは表の点数だけで、日付・メモ・名簿は持たない
/// （CSVはディレクトリの画面から取り込む → CSVImportView）。
/// こちらは `GameSnapshot` をそのままJSONにしたもので、日付・メモごと丸ごと戻せる。
struct BackupView: View {
    let board: ScoreBoard
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<SavedGame> { !$0.isDraft }, sort: \SavedGame.savedAt, order: .reverse)
    private var records: [SavedGame]
    @Query(sort: [SortDescriptor(\Directory.sortOrder), SortDescriptor(\Directory.createdAt)])
    private var directories: [Directory]

    @State private var pasted = ""
    @State private var plan: ImportResult?
    @State private var failure: String?
    @State private var done: String?
    @State private var didCopy = false

    var body: some View {
        NavigationStack {
            Form {
                exportSection
                importSection
                if let plan { planSection(plan) }
            }
            .navigationTitle("バックアップ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }.bold()
                }
            }
            .alert("取り込めませんでした", isPresented: presenting($failure)) {
                Button("OK", role: .cancel) { failure = nil }
            } message: {
                Text(failure ?? "")
            }
            .alert("取り込みました", isPresented: presenting($done)) {
                Button("OK", role: .cancel) { done = nil }
            } message: {
                Text(done ?? "")
            }
        }
    }

    // MARK: - 書き出し

    private var exportSection: some View {
        Section {
            Button {
                UIPasteboard.general.string = exportText()
                didCopy = true
                Task {
                    try? await Task.sleep(for: .seconds(1.8))
                    didCopy = false
                }
            } label: {
                Label(didCopy ? "コピーしました" : "バックアップをコピー",
                      systemImage: didCopy ? "checkmark.circle.fill" : "doc.on.doc")
                    .foregroundStyle(didCopy ? Palette.accent : Color.accentColor)
            }
            .disabled(records.isEmpty)
            .accessibilityIdentifier("copyBackup")

            if let text = try? exportData(), !records.isEmpty {
                ShareLink(item: text) {
                    Label("ファイルとして送る", systemImage: "square.and.arrow.up")
                }
            }
        } header: {
            Text("書き出し")
        } footer: {
            Text(records.isEmpty
                 ? "保存した記録がまだありません。"
                 : "保存した記録 \(records.count) 件をまとめて書き出します。メモにそのまま貼るか、自分宛てに送っておけば、機種変更や端末の故障のときに戻せます。")
        }
    }

    private func exportText() -> String {
        (try? exportData()) ?? ""
    }

    private func exportData() throws -> String {
        let games = records.compactMap { record -> BackupGame? in
            guard let snapshot = try? record.snapshot() else { return nil }
            return BackupGame(uid: record.uid, playedAt: record.effectivePlayedAt,
                              savedAt: record.savedAt, note: record.note, snapshot: snapshot,
                              directoryId: record.directoryId ?? Directory.defaultUID)
        }
        // 受け取っているフォルダは人のもの。自分で作ったフォルダだけ書き出す。
        // **共有のIDとパスワードは入れない**（ファイルが人に渡ると共有を書き換えられる）
        let folders = directories.filter { !$0.isSubscribed }.map {
            BackupDirectory(uid: $0.uid, name: $0.name, sortOrder: $0.sortOrder)
        }
        let data = try Backup.encode(BackupFile(games: games, directories: folders))
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - 取り込み

    private var importSection: some View {
        Section {
            TextEditor(text: $pasted)
                .frame(minHeight: 90)
                .font(.system(size: 12, design: .monospaced))
                .accessibilityIdentifier("backupPasteField")

            HStack {
                // CSVの取り込みと同じ入口。長押しで貼るより早い
                PasteButton(payloadType: String.self) { strings in
                    Task { @MainActor in pasted = strings.joined(separator: "\n") }
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier("pasteBackup")

                Spacer()

                Button {
                    preview()
                } label: {
                    Label("中身を確かめる", systemImage: "eye")
                }
                .buttonStyle(.borderless)
                .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("previewImport")
            }
        } header: {
            Text("取り込み")
        } footer: {
            Text("書き出したバックアップを貼り付けてください。**取り込む前に、何件入って何件飛ぶかをお見せします。** 同じ対局は二度入りません。フォルダ分けもそのまま戻ります（共有のIDとパスワードは書き出しに含めないので、共有はもう一度設定してください）。")
        }
    }

    /// 貼り付けたバックアップに入っていたフォルダ。取り込むときに作り直す
    @State private var pastedDirectories: [BackupDirectory] = []

    private func preview() {
        do {
            let file = try Backup.decode(pasted)
            pastedDirectories = file.directories
            plan = Backup.plan(file: file,
                               existingUIDs: Set(records.map(\.uid)),
                               decimalMode: board.decimalMode)
        } catch let error as BackupError {
            plan = nil
            failure = message(for: error)
        } catch {
            plan = nil
            failure = "読み取れない形式でした。"
        }
    }

    private func message(for error: BackupError) -> String {
        switch error {
        case .notJSON:
            return "バックアップの形式ではありません。CSVを貼るときは、記録の画面でディレクトリを開き、右上のメニューの「CSVを貼って取り込む」から入れてください。"
        case .notJansanBackup:
            return "雀算のバックアップではないようです。"
        case .tooNew(let version):
            return "新しい形式（v\(version)）のバックアップです。App Store で雀算を最新にしてから取り込んでください。"
        }
    }

    @ViewBuilder
    private func planSection(_ plan: ImportResult) -> some View {
        Section {
            LabeledContent("新しく入る", value: "\(plan.added.count) 件")
            if plan.skipped > 0 {
                LabeledContent("すでにあるので飛ばす", value: "\(plan.skipped) 件")
            }
            if plan.broken > 0 {
                LabeledContent("読めなかった", value: "\(plan.broken) 件")
            }
            if !plan.decimalMismatch.isEmpty {
                Label("表示モードが違う記録が \(plan.decimalMismatch.count) 件あります",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Palette.negative)
            }

            Button {
                commit(plan)
            } label: {
                Label("この内容で取り込む", systemImage: "square.and.arrow.down")
            }
            .disabled(plan.added.isEmpty)
            .accessibilityIdentifier("commitImport")
        } header: {
            Text("取り込む内容")
        } footer: {
            if plan.decimalMismatch.isEmpty {
                Text("いま入っている記録は消えません。追加だけです。")
            } else {
                // 過去に踏んだ不具合。混ぜると点数が10倍に見える
                Text("いま入っている記録は消えません。ただし、小数点モードの設定が違う記録が混ざっています。取り込むこと自体は問題ありませんが、集計で混ぜると点数が10倍ズレて見えます。ビューの「表示モード」で分けて見てください。")
            }
        }
    }

    private func commit(_ plan: ImportResult) {
        // **フォルダ分けごと戻す。** 無いフォルダは名前も並び順もそのまま作り直す
        var restoredFolders = 0
        for folder in pastedDirectories where !directories.contains(where: { $0.uid == folder.uid }) {
            DirectoryStore.ensure(uid: folder.uid, name: folder.name,
                                  sortOrder: folder.sortOrder, in: context)
            restoredFolders += 1
        }
        let known = Set(directories.map(\.uid)).union(pastedDirectories.map(\.uid))

        var inserted = 0
        for game in plan.added {
            guard let record = try? SavedGame(snapshot: game.snapshot, isDraft: false,
                                              savedAt: game.savedAt, playedAt: game.playedAt,
                                              note: game.note, uid: game.uid) else { continue }
            // 元のフォルダが分からない古いバックアップは、これまでどおり「マイ記録」へ
            if let id = game.directoryId, known.contains(id) || id == Directory.defaultUID {
                record.directoryId = id
            }
            context.insert(record)
            inserted += 1
        }
        try? context.save()
        self.plan = nil
        pasted = ""
        pastedDirectories = []
        done = restoredFolders > 0
            ? "\(inserted) 件の記録を追加し、フォルダを \(restoredFolders) 個作り直しました。"
            : "\(inserted) 件の記録を追加しました。"
    }

    private func presenting<T>(_ value: Binding<T?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
    }
}
