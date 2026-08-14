import SwiftUI
import SwiftData

struct HistoryView: View {
    let board: ScoreBoard
    @Environment(\.dismiss) private var dismiss

    // 下書き(作業中の状態)は履歴に出さない
    @Query(
        filter: #Predicate<SavedGame> { !$0.isDraft },
        sort: \SavedGame.savedAt,
        order: .reverse
    )
    private var records: [SavedGame]

    @Environment(\.modelContext) private var context
    @State private var pendingLoad: SavedGame?

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
                            Button {
                                pendingLoad = record
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.dateLabel)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(Palette.ink)
                                    Text(record.summaryLine)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Palette.inkDim)
                                }
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("保存した記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .alert("この記録を読み込みますか", isPresented: .constant(pendingLoad != nil)) {
                Button("キャンセル", role: .cancel) { pendingLoad = nil }
                Button("読み込む") {
                    if let record = pendingLoad { board.load(record) }
                    pendingLoad = nil
                    dismiss()
                }
            } message: {
                Text("現在入力中の内容は上書きされます。")
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(records[index])
        }
        try? context.save()
    }
}
