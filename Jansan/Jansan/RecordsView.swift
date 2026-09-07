import SwiftUI
import SwiftData
import JansanCore

/// 「記録」タブ。ディレクトリの一覧。
///
/// 自分のディレクトリも、受け取ったディレクトリも同じ行で並ぶ。
/// 違いは行の2行目（「共有中」「共有されたもの」）だけ。
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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(directories) { dir in
                        NavigationLink(value: dir.uid) {
                            row(dir)
                        }
                        .accessibilityIdentifier("directory-\(dir.uid.uuidString)")
                    }
                } footer: {
                    Text("記録は「ディレクトリ」に分けて残せます。卓や面子ごとに分けておくと、あとで集計するときに混ざりません。共有すると、IDとパスワードを知っている人が同じものを見られます。")
                }
            }
            .navigationTitle("記録")
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
            .sheet(isPresented: $showSubscribe) {
                SubscribeView()
            }
        }
    }

    private func row(_ dir: Directory) -> some View {
        let count = allGames.filter { ($0.directoryId ?? Directory.defaultUID) == dir.uid }.count
        let isCurrent = dir.uid.uuidString == currentDirectoryID
        return HStack(spacing: 12) {
            Image(systemName: dir.isSubscribed ? "person.2.fill" : (dir.isShared ? "antenna.radiowaves.left.and.right" : "folder.fill"))
                .foregroundStyle(dir.isSubscribed ? Palette.toneBInk : Palette.accent)
                .frame(width: 24)
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
                Text("\(count) 件・\(dir.subtitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let order = (directories.map(\.sortOrder).max() ?? 0) + 1
        context.insert(Directory(name: name, sortOrder: order))
        try? context.save()
    }
}
