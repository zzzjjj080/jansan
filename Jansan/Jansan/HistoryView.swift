import SwiftUI
import SwiftData

struct HistoryView: View {
    let board: ScoreBoard
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    // 下書き(作業中の状態)は履歴に出さない
    @Query(
        filter: #Predicate<SavedGame> { !$0.isDraft },
        sort: \SavedGame.savedAt,
        order: .reverse
    )
    private var records: [SavedGame]

    @State private var pendingLoad: SavedGame?
    @State private var pendingDelete: SavedGame?

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView(
                        "まだ記録がありません",
                        systemImage: "tray",
                        description: Text("「保存」を押すと、その時点の表が日付付きで残ります。")
                    )
                } else {
                    List {
                        ForEach(records) { record in
                            row(record)
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("保存した記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // EditButtonはアプリを日本語化するまで英語表記になるうえ、
                // 各行のゴミ箱ボタンとスワイプ削除で用は足りるので置かない
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .alert("この記録を読み込みますか", isPresented: presenting($pendingLoad)) {
                Button("キャンセル", role: .cancel) { pendingLoad = nil }
                Button("読み込む") {
                    if let record = pendingLoad { board.load(record) }
                    pendingLoad = nil
                    dismiss()
                }
            } message: {
                Text("現在入力中の内容は上書きされます。")
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
                pendingLoad = record
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
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            // スワイプに気づかなくても消せるよう、明示的な削除ボタンも置く
            Button {
                pendingDelete = record
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Palette.negative)
            }
            .buttonStyle(.plain)
        }
    }

    /// Optional を alert の isPresented に橋渡しする
    private func presenting<T>(_ value: Binding<T?>) -> Binding<Bool> {
        Binding(
            get: { value.wrappedValue != nil },
            set: { if !$0 { value.wrappedValue = nil } }
        )
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(records[index])
        }
        try? context.save()
    }

    private func remove(_ record: SavedGame) {
        context.delete(record)
        try? context.save()
    }
}
