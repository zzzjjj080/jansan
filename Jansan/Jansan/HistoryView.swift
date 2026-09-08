import SwiftUI
import SwiftData

/// ディレクトリ1つぶんの記録の一覧。DirectoryView の中身として置かれる
struct HistoryView: View {
    let board: ScoreBoard
    let directory: Directory
    var goToInput: () -> Void = {}
    @Environment(\.modelContext) private var context

    // 下書き(作業中の状態)は履歴に出さない
    @Query(
        filter: #Predicate<SavedGame> { !$0.isDraft },
        sort: \SavedGame.savedAt,
        order: .reverse
    )
    private var allRecords: [SavedGame]

    /// このディレクトリの分だけ。directoryId が nil の古い記録は「マイ記録」
    private var records: [SavedGame] {
        allRecords.filter { ($0.directoryId ?? Directory.defaultUID) == directory.uid }
    }

    @State private var viewing: SavedGame?
    @State private var pendingDelete: SavedGame?
    @State private var editing: SavedGame?
    @State private var query = ""

    /// 記録が増えると一覧から目当てを探せなくなる。名前・メモ・日付のどれでも引ける
    private var shown: [SavedGame] {
        let key = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return records }
        return records.filter { $0.searchText.contains(key) }
    }

    var body: some View {
        Group {
            Group {
                if records.isEmpty {
                    ContentUnavailableView(
                        "まだ記録がありません",
                        systemImage: "tray",
                        description: Text(directory.isSubscribed
                                          ? "送り主がまだ記録を入れていません。"
                                          : "入力画面の保存ボタン（下向き矢印）を押すと、その時点の表が日付付きでここに残ります。")
                    )
                } else if shown.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List {
                        ForEach(shown) { record in
                            row(record)
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            // 大見出しの画面では、既定だと検索欄が引っ込んで下に引かないと出ない。常に出す
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "名前・メモ・日付で探す")
            .listStyle(.insetGrouped)
            .sheet(item: $editing) { record in
                RecordEditView(record: record)
            }
            .sheet(item: $viewing) { record in
                GameDetailView(record: record, directory: directory, board: board, goToInput: goToInput)
            }
            .alert("この記録を削除しますか", isPresented: presenting($pendingDelete)) {
                Button("キャンセル", role: .cancel) { pendingDelete = nil }
                Button("削除", role: .destructive) {
                    if let record = pendingDelete { remove(record) }
                    pendingDelete = nil
                }
            } message: {
                Text("この操作は元に戻せません。")
            }
        }
    }

    private func row(_ record: SavedGame) -> some View {
        HStack {
            Button {
                viewing = record
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(record.dateLabel)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Palette.ink)
                        Text(record.shapeLabel)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Palette.accent.opacity(0.12), in: Capsule())
                    }
                    Text(record.summaryLine)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.inkDim)

                    if !record.note.isEmpty {
                        Label(record.note, systemImage: "text.quote")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.toneAInk)
                            .lineLimit(2)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            if directory.isEditable {
                Button {
                    editing = record
                } label: {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("日付とメモを編集")
            }

            // スワイプに気づかなくても消せるよう、明示的な削除ボタンも置く。
            // 受け取ったものは消さない。「最新を受け取る」で戻ってくるだけなので
            if directory.isEditable {
                Button {
                    pendingDelete = record
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Palette.negative)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Optional を alert の isPresented に橋渡しする
    private func presenting<T>(_ value: Binding<T?>) -> Binding<Bool> {
        Binding(
            get: { value.wrappedValue != nil },
            set: { if !$0 { value.wrappedValue = nil } }
        )
    }

    /// 検索で絞っているときは、画面に出ている並びから消す。
    /// records の添字で消すと**別の記録が消える**
    private func delete(at offsets: IndexSet) {
        guard directory.isEditable else { return }
        for index in offsets {
            context.delete(shown[index])
        }
        markDirty()
        try? context.save()
    }

    private func markDirty() {
        if directory.isShared {
            directory.needsPublish = true
            directory.updatedAt = .now
        }
    }

    private func remove(_ record: SavedGame) {
        markDirty()
        context.delete(record)
        try? context.save()
    }
}
