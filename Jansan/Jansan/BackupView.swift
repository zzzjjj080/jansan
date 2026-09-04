import SwiftUI
import SwiftData
import JansanCore

/// 記録のバックアップと取り込み。
///
/// **CSVとは別物。** CSVは合計行つき・お休みは空欄・小数変換済みで、
/// 人が読むためのもの。あれを読み戻して表を復元することはできない。
/// こちらは `GameSnapshot` をそのままJSONにしたもので、復元できる。
struct BackupView: View {
    let board: ScoreBoard
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<SavedGame> { !$0.isDraft }, sort: \SavedGame.savedAt, order: .reverse)
    private var records: [SavedGame]

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
                              savedAt: record.savedAt, note: record.note, snapshot: snapshot)
        }
        let data = try Backup.encode(BackupFile(games: games))
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - 取り込み

    private var importSection: some View {
        Section {
            TextEditor(text: $pasted)
                .frame(minHeight: 90)
                .font(.system(size: 12, design: .monospaced))
                .accessibilityIdentifier("backupPasteField")

            Button {
                preview()
            } label: {
                Label("中身を確かめる", systemImage: "eye")
            }
            .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("previewImport")
        } header: {
            Text("取り込み")
        } footer: {
            Text("書き出したバックアップを貼り付けてください。**取り込む前に、何件入って何件飛ぶかをお見せします。** 同じ対局は二度入りません。")
        }
    }

    private func preview() {
        do {
            let file = try Backup.decode(pasted)
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
            return "バックアップの形式ではありません。CSVを貼っていませんか。CSVからは記録を戻せないので、書き出しでコピーしたものを貼ってください。"
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
        var inserted = 0
        for game in plan.added {
            guard let record = try? SavedGame(snapshot: game.snapshot, isDraft: false,
                                              savedAt: game.savedAt, playedAt: game.playedAt,
                                              note: game.note, uid: game.uid) else { continue }
            context.insert(record)
            inserted += 1
        }
        try? context.save()
        self.plan = nil
        pasted = ""
        done = "\(inserted) 件の記録を追加しました。"
    }

    private func presenting<T>(_ value: Binding<T?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
    }
}
