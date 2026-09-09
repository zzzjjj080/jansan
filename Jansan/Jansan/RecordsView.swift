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

    @State private var showNew = false
    @State private var showSubscribe = false
    @State private var newName = ""
    @State private var pendingDelete: Directory?

    private var mine: [Directory] { directories.filter { !$0.isSubscribed } }
    private var received: [Directory] { directories.filter(\.isSubscribed) }

    /// 受け取ったものの色。自分のもの（緑）とはっきり変える
    private var receivedTint: Color { Palette.toneCInk }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(mine) { dir in
                        NavigationLink(value: dir.uid) { row(dir, tint: Palette.accent) }
                            .accessibilityIdentifier("directory-\(dir.uid.uuidString)")
                    }
                    .onDelete { offsets in
                        // 「マイ記録」は消せない。中の記録の行き先が無くなる
                        if let index = offsets.first, mine[index].isDefault == false {
                            pendingDelete = mine[index]
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
                            NavigationLink(value: dir.uid) { row(dir, tint: receivedTint) }
                                .accessibilityIdentifier("directory-\(dir.uid.uuidString)")
                                .listRowBackground(receivedTint.opacity(0.10))
                        }
                        .onDelete { offsets in
                            if let index = offsets.first { pendingDelete = received[index] }
                        }
                    } header: {
                        Label("共有されたもの", systemImage: "person.2.fill")
                            .foregroundStyle(receivedTint)
                            .font(.footnote.weight(.bold))
                    } footer: {
                        Text("他の人から受け取った記録です。見るだけで、書き換えることはできません。開くと自動で最新を取りに行きます。")
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
                            showSubscribe = true
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
            .sheet(isPresented: $showSubscribe) {
                SubscribeView()
            }
            // 一覧を開いたら、受け取っているものを静かに取り直す。
            // 件数が古いままだと「更新されない」と見える
            .task {
                await SharePublisher.refreshSubscriptions(in: context)
            }
            .refreshable {
                await SharePublisher.refreshSubscriptions(in: context)
            }
        }
    }

    private func row(_ dir: Directory, tint: Color) -> some View {
        let count = allGames.filter { ($0.directoryId ?? Directory.defaultUID) == dir.uid }.count
        let isCurrent = dir.uid.uuidString == currentDirectoryID
        return HStack(spacing: 12) {
            Image(systemName: dir.isSubscribed ? "person.2.fill" : (dir.isShared ? "antenna.radiowaves.left.and.right" : "folder.fill"))
                .font(.system(size: 18))
                .foregroundStyle(tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(dir.name).font(.body.weight(.semibold))
                    if isCurrent {
                        Text("保存先")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Palette.accentInk)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Palette.accent, in: Capsule())
                    }
                }
                Text("\(count) 件 ・ \(dir.subtitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
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
