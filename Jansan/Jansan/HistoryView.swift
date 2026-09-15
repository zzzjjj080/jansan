import SwiftUI
import SwiftData
import JansanCore

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

    /// このディレクトリの分だけ。directoryId が nil の古い記録は「マイ記録」。
    /// **対局日の新しい順に並べる。** 保存した順だと、後日まとめて入れた記録や
    /// CSV で取り込んだ記録が上に来て、いつの対局か追えない。日付未記入は最後
    private var records: [SavedGame] {
        allRecords
            .filter { ($0.directoryId ?? Directory.defaultUID) == directory.uid }
            .sorted {
                PlayedDate.newestFirst(played: $0.playedAt, saved: $0.savedAt,
                                       before: $1.playedAt, saved: $1.savedAt)
            }
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
                                          : "・入力画面の保存ボタン（フロッピー）を押すと、その時点の表がここに残ります\n・右上のメニューから、CSVを貼って取り込むこともできます")
                    )
                } else if shown.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List {
                        ForEach(shown) { record in
                            row(record)
                                // 受け取った記録は消せない。スワイプの削除を出すと、断っても行だけ消えて
                                // 一覧の数が食い違う（RecordsView と同じ理由）
                                .deleteDisabled(!directory.isEditable)
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            // 大見出しの画面では、既定だと検索欄が引っ込んで下に引かないと出ない。常に出す
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "名前・メモ・日付で探す")
            .listStyle(.insetGrouped)
            // 共有中・受け取り中なら、IDとパスワードを一番上に出す（一覧には出さない）
            .safeAreaInset(edge: .top, spacing: 0) { shareInfo }
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

    /// 共有中のとき、何人が受け取っているか（受け取り票の枚数と、最後に見た日時）
    @State private var receipts: ShareReceipt.Summary?
    @State private var receiptsLoaded = false

    private var receiptLine: String {
        guard receiptsLoaded else { return "受け取っている人を数えています…" }
        guard let receipts else { return "受け取っている人を数えられませんでした（通信できません）" }
        guard receipts.count > 0 else { return "まだ誰も受け取っていません" }
        let last = receipts.lastSeen.map {
            " ・ 最後に見たのは \($0.formatted(.dateTime.month().day().locale(Locale(identifier: "ja_JP"))))"
        } ?? ""
        return "\(receipts.count)人が受け取り中\(last)"
    }

    /// 共有しているとき（受け取っているとき）の ID とパスワード。人に伝えるときに読めるよう、長押しで選べる
    @ViewBuilder
    private var shareInfo: some View {
        if directory.isShared || directory.isSubscribed {
            HStack(spacing: 10) {
                Image(systemName: directory.isSubscribed ? "person.2.fill" : "antenna.radiowaves.left.and.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(directory.isSubscribed ? "受け取り中" : "共有中")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.inkDim)
                    Text("ID \(directory.shareID) ・ パスワード \(directory.sharePassword)")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                    // 送った側だけ。受け取った端末が置いた票を数える（iCloud にサインインしている端末だけが数に入る）
                    if directory.isShared {
                        Text(receiptLine)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("shareInfo")
            .task(id: directory.shareID + directory.sharePassword) {
                guard directory.isShared else { return }
                receipts = await ShareClient.receiptSummary(id: directory.shareID, password: directory.sharePassword)
                receiptsLoaded = true
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
