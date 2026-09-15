import SwiftUI
import SwiftData
import JansanCore

/// 「記録」側。ディレクトリの一覧。
///
/// **自分のものと受け取ったものは枠を分ける。** 同じ行で混ぜると、どれが
/// 自分の記録でどれが人のものか分からなくなる。受け取ったものは色も変える。
struct RecordsView: View {
    let board: ScoreBoard
    var goToInput: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Directory.sortOrder), SortDescriptor(\Directory.createdAt)])
    private var directories: [Directory]
    @Query(filter: #Predicate<SavedGame> { !$0.isDraft }) private var allGames: [SavedGame]
    @AppStorage("currentDirectory") private var currentDirectoryID = Directory.defaultUID.uuidString
    @AppStorage(Directory.allowDeletingKey) private var allowDeletingWithRecords = false
    /// 記録が多くて削除を断ったディレクトリ
    @State private var lockedDelete: Directory?

    @State private var showNew = false
    /// シートは1本にまとめる。1つの画面に .sheet を複数付けると、どれかが開かなくなることがある
    @State private var sheet: RecordsSheet?
    /// 行に NavigationLink を置くと、一覧が右端に「＞」を付けて行ごと押せるようにしてしまう。
    /// 「詳細」ボタンから入るので、行き先は自分で積む
    @State private var path: [UUID] = []

    private enum RecordsSheet: Identifiable {
        case subscribe
        case stats(UUID)

        var id: String {
            switch self {
            case .subscribe: "subscribe"
            case .stats(let uid): "stats-\(uid.uuidString)"
            }
        }
    }
    @State private var newName = ""
    @State private var pendingDelete: Directory?

    /// 自動バックアップは自分のものだが、一覧では**共有されたものより下**に別枠で置く（本人の指示）
    private var mine: [Directory] { directories.filter { !$0.isSubscribed && !$0.isAutoBackup } }
    private var autoBackup: Directory? { directories.first(where: \.isAutoBackup) }
    private var received: [Directory] { directories.filter(\.isSubscribed) }

    /// 受け取ったものの色。自分のもの（緑）とはっきり変える
    private var receivedTint: Color { Palette.toneCInk }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(mine) { dir in
                        directoryCell(dir, tint: Palette.accent)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                // 「マイ記録」は消せない。中の記録の行き先が無くなるので、削除の操作ごと出さない
                                if !dir.isDefault { deleteAction(dir) }
                            }
                    }
                } header: {
                    Text("自分の記録")
                } footer: {
                    Text("卓や面子ごとに分けておくと、集計するときに混ざりません。共有すると、IDとパスワードを知っている人が同じものを見られます。")
                }

                if !received.isEmpty {
                    Section {
                        ForEach(received) { dir in
                            directoryCell(dir, tint: receivedTint)
                                .listRowBackground(receivedTint.opacity(0.10))
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    deleteAction(dir)
                                }
                        }
                    } header: {
                        Label("共有されたもの", systemImage: "person.2.fill")
                            .foregroundStyle(receivedTint)
                            .font(.footnote.weight(.bold))
                    } footer: {
                        Text("他の人から受け取った記録です。見るだけで、書き換えることはできません。開くと自動で最新を取りに行きます。")
                    }
                }

                if let backup = autoBackup {
                    Section {
                        directoryCell(backup, tint: Palette.accent)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                // 空になった控えの置き場は押せない状態なので、削除も出さない
                                if count(of: backup) > 0 { deleteAction(backup) }
                            }
                    } footer: {
                        Text("「新しい対局を始める」の前の表を控えています。記録されてから1か月たった控えは自動で消えます。")
                    }
                }
            }
            // 「記録」という見出しは要らない。上の切り替えで今どちらにいるかは分かる
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { uid in
                if let dir = directories.first(where: { $0.uid == uid }) {
                    DirectoryView(directory: dir, board: board, goToInput: goToInput)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            newName = ""
                            showNew = true
                        } label: {
                            Label("新しいディレクトリ", systemImage: "folder.badge.plus")
                        }
                        .accessibilityIdentifier("newDirectory")
                        Button {
                            sheet = .subscribe
                        } label: {
                            Label("IDで受け取る", systemImage: "square.and.arrow.down")
                        }
                        .accessibilityIdentifier("subscribeDirectory")
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("addDirectory")
                }
            }
            .alert("新しいディレクトリ", isPresented: $showNew) {
                TextField("例：田中宅", text: $newName)
                Button("作る") { create() }
                Button("やめる", role: .cancel) {}
            } message: {
                Text("卓や面子の名前を付けておくと分かりやすくなります。")
            }
            .alert(pendingDelete?.isSubscribed == true ? "受け取るのをやめますか" : "このディレクトリを削除しますか",
                   isPresented: Binding(get: { pendingDelete != nil },
                                        set: { if !$0 { pendingDelete = nil } })) {
                Button("やめる", role: .cancel) { pendingDelete = nil }
                Button("削除する", role: .destructive) { deletePending() }
            } message: {
                Text(deleteMessage)
            }
            .alert("このフォルダは削除できません",
                   isPresented: Binding(get: { lockedDelete != nil }, set: { if !$0 { lockedDelete = nil } })) {
                Button("OK", role: .cancel) { lockedDelete = nil }
            } message: {
                Text(lockedDelete.map { DirectoryStore.deletionLockedMessage($0, in: context) } ?? "")
            }
            .sheet(item: $sheet) { kind in
                switch kind {
                case .subscribe:
                    SubscribeView()
                case .stats(let uid):
                    if let dir = directories.first(where: { $0.uid == uid }) {
                        AllStatsView(directory: dir)
                    }
                }
            }
            // 一覧を開いたら、受け取っているものを静かに取り直す。
            // 件数が古いままだと「更新されない」と見える
            .task {
                DirectoryStore.pruneAutoBackups(in: context)
                await SharePublisher.refreshSubscriptions(in: context)
            }
            .refreshable {
                await SharePublisher.refreshSubscriptions(in: context)
            }
        }
    }

    /// スワイプの削除。**確認を出すだけで、ここでは消さない。**
    ///
    /// `onDelete` を使わない。`onDelete` は押した瞬間に一覧から行を消す前提で動くので、
    /// 確認を挟んだり削除を断ったりすると、行だけ消えてデータは残る。そのまま別の画面へ進むと
    /// 一覧の数が合わず UICollectionView が落ちた（2026-09-13 実機。引き継ぎ書 4-128）。
    /// 役割も `.destructive` にしない。付けると同じように行が先に消える
    private func deleteAction(_ dir: Directory) -> some View {
        Button {
            // 記録が多いディレクトリは、設定でオンにしていなければ確認にも進ませない
            if DirectoryStore.isDeletionLocked(dir, in: context, allowed: allowDeletingWithRecords) {
                lockedDelete = dir
            } else {
                pendingDelete = dir
            }
        } label: {
            Label("削除", systemImage: "trash")
        }
        .tint(Palette.negative)
    }

    /// 一覧の1行。上に名前（件数）と印、下に大きな「詳細」「集計」の2つのボタン。
    ///
    /// **中に入るのは「詳細」ボタンからだけ**（本人の指示）。行のほかの場所を押しても何も起きない。
    /// 右端に「＞」は付けない。1行に複数のボタンを置くときは、どれも `.borderless` にする
    /// （一覧はそうしないと、行のどこを押しても全部のボタンが反応する）
    ///
    /// **自動バックアップが期限切れで0件になったら、行ごと灰色にして押せなくする**（本人の指示）
    private func directoryCell(_ dir: Directory, tint: Color) -> some View {
        let isEmptyBackup = dir.isAutoBackup && count(of: dir) == 0
        let tint = isEmptyBackup ? Palette.inkDim : tint
        return VStack(alignment: .leading, spacing: 12) {
            row(dir, tint: tint)
                .accessibilityIdentifier("directory-\(dir.uid.uuidString)")

            HStack(spacing: 10) {
                detailButton(dir, tint: tint)
                // 自動バックアップは控えの置き場。集計する対象ではない
                if !dir.isAutoBackup {
                    statsButton(dir, tint: tint)
                }
            }
        }
        .padding(.vertical, 6)
        .disabled(isEmptyBackup)
        .opacity(isEmptyBackup ? 0.5 : 1)
    }

    /// ディレクトリの記録の件数。directoryId が nil の古い記録は「マイ記録」に数える
    private func count(of dir: Directory) -> Int {
        allGames.filter { ($0.directoryId ?? Directory.defaultUID) == dir.uid }.count
    }

    private func detailButton(_ dir: Directory, tint: Color) -> some View {
        Button {
            path.append(dir.uid)
        } label: {
            cellButtonLabel("詳細", systemImage: "list.bullet.rectangle", tint: tint, filled: false)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("「\(dir.name)」の記録を開く")
        .accessibilityIdentifier("openDirectory-\(dir.uid.uuidString)")
    }

    /// **中に入らずに、そのディレクトリの集計を開く。** 以前は中に入ってから右上の集計を押す必要があった
    private func statsButton(_ dir: Directory, tint: Color) -> some View {
        Button {
            sheet = .stats(dir.uid)
        } label: {
            cellButtonLabel("集計", systemImage: "chart.line.uptrend.xyaxis", tint: tint, filled: true)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("「\(dir.name)」の集計を開く")
        .accessibilityIdentifier("openStats-\(dir.uid.uuidString)")
    }

    /// 「詳細」「集計」の見た目。指で押しやすい大きさにし、2つで行の幅を分け合う
    private func cellButtonLabel(_ title: String, systemImage: String, tint: Color, filled: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(tint.opacity(filled ? 0.22 : 0.10), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(0.45), lineWidth: 1))
            .contentShape(Rectangle())
    }

    /// 名前の行。件数は名前のあとに（9）の形で添える。
    /// **IDとパスワードは一覧に出さない**（詳細を開いた一番上に出す）。共有中・保存先は名前の横の丸い印で見せる
    private func row(_ dir: Directory, tint: Color) -> some View {
        let recordCount = count(of: dir)
        let isCurrent = dir.uid.uuidString == currentDirectoryID
        let symbol = dir.isSubscribed ? "person.2.fill"
            : dir.isShared ? "antenna.radiowaves.left.and.right"
            : dir.isAutoBackup ? "clock.arrow.circlepath"
            : "folder.fill"
        return HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            Text("\(dir.name)（\(recordCount)）")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if isCurrent {
                badge("保存先", tint: Palette.accent, filled: true)
            }
            if dir.isShared {
                badge("共有中", tint: tint, filled: false)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// 名前の横の丸い印（保存先・共有中）
    private func badge(_ text: String, tint: Color, filled: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(filled ? Palette.accentInk : tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(filled ? tint : tint.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(filled ? 0 : 0.6), lineWidth: 1))
            .fixedSize()
    }

    private var deleteMessage: String {
        guard let dir = pendingDelete else { return "" }
        if dir.isSubscribed {
            return "この端末に取り込んだぶんは消えます。送り主の記録には影響しません。また同じIDとパスワードで受け取れます。"
        }
        return "「\(dir.name)」の中の記録 \(DirectoryStore.gameCount(of: dir, in: context)) 件も一緒に消えます。元に戻せません。共有中なら、公開されたものも消します。"
    }

    private func deletePending() {
        guard let dir = pendingDelete else { return }
        if dir.isShared {
            let id = dir.shareID, pw = dir.sharePassword
            Task { try? await ShareClient.unpublish(id: id, password: pw) }
        }
        // 受け取るのをやめるなら、送り主から見た人数から外れるよう票を消す
        if dir.isSubscribed {
            let id = dir.shareID, pw = dir.sharePassword
            Task { await ShareClient.removeReceipt(id: id, password: pw) }
        }
        for game in DirectoryStore.games(of: dir, in: context) { context.delete(game) }
        if dir.uid.uuidString == currentDirectoryID {
            currentDirectoryID = Directory.defaultUID.uuidString
        }
        context.delete(dir)
        try? context.save()
        pendingDelete = nil
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let order = (directories.map(\.sortOrder).max() ?? 0) + 1
        context.insert(Directory(name: name, sortOrder: order))
        try? context.save()
    }
}
