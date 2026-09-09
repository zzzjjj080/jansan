import SwiftUI
import SwiftData

/// 保存先のディレクトリを選ぶ。入力画面のいちばん左のボタンから開く。
///
/// 受け取ったディレクトリは書き込めないので出さない。
struct DirectoryPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Directory.sortOrder), SortDescriptor(\Directory.createdAt)])
    private var directories: [Directory]
    @AppStorage("currentDirectory") private var currentDirectoryID = Directory.defaultUID.uuidString

    @State private var showNew = false
    @State private var newName = ""

    private var choices: [Directory] { directories.filter(\.isEditable) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(choices) { dir in
                        Button {
                            currentDirectoryID = dir.uid.uuidString
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: dir.isShared ? "antenna.radiowaves.left.and.right" : "folder.fill")
                                    .foregroundStyle(dir.isShared ? Palette.toneAInk : Palette.accent)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dir.name).foregroundStyle(Palette.ink)
                                    Text(DirectoryStore.subtitle(of: dir, in: context))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if dir.uid.uuidString == currentDirectoryID {
                                    Image(systemName: "checkmark").foregroundStyle(Palette.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("pick-\(dir.uid.uuidString)")
                    }
                } footer: {
                    Text("次に「記録に残す」を押したとき、ここで選んだディレクトリに入ります。共有中のディレクトリを選ぶと、受け取っている人にも届きます。")
                }

                Section {
                    Button {
                        newName = ""
                        showNew = true
                    } label: {
                        Label("新しいディレクトリ", systemImage: "folder.badge.plus")
                    }
                    .accessibilityIdentifier("pickerNewDirectory")
                }
            }
            .navigationTitle("保存先")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("やめる") { dismiss() }
                }
            }
            .alert("新しいディレクトリ", isPresented: $showNew) {
                TextField("例：田中宅", text: $newName)
                Button("作って選ぶ") { create() }
                Button("やめる", role: .cancel) {}
            } message: {
                Text("卓や面子の名前を付けておくと分かりやすくなります。")
            }
        }
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let dir = Directory(name: name, sortOrder: (directories.map(\.sortOrder).max() ?? 0) + 1)
        context.insert(dir)
        try? context.save()
        currentDirectoryID = dir.uid.uuidString
        dismiss()
    }
}
