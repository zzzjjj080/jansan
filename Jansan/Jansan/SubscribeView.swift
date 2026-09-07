import SwiftUI
import SwiftData
import JansanCore

/// 他の人のディレクトリを ID＋パスワードで受け取る。
///
/// 入れる → 中身を確かめる（名前と件数を見せる）→ 追加、の3段。
/// 追加する前に何が入ってくるかを見せるのは、取り込み全般と同じ方針。
struct SubscribeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var directories: [Directory]

    @State private var shareID = ""
    @State private var password = ""
    @State private var working = false
    @State private var preview: SharedDirectoryDocument?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ID", text: $shareID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .accessibilityIdentifier("subscribeIDField")
                    TextField("パスワード", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .accessibilityIdentifier("subscribePasswordField")
                } header: {
                    Text("送り主から聞いたもの")
                } footer: {
                    Text("大文字と小文字は区別しません。")
                }

                Section {
                    Button {
                        Task { await lookUp() }
                    } label: {
                        HStack {
                            Label(working ? "探しています…" : "中身を確かめる", systemImage: "magnifyingglass")
                            if working { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(working || shareID.isEmpty || password.isEmpty)
                    .accessibilityIdentifier("lookUpButton")
                }

                if let preview {
                    Section {
                        LabeledContent("名前", value: preview.name)
                        LabeledContent("記録", value: "\(preview.backup.games.count) 件")
                        LabeledContent("表示モード", value: preview.decimalMode ? "小数" : "整数")
                        Button {
                            subscribe(preview)
                        } label: {
                            Label("受け取る", systemImage: "square.and.arrow.down")
                        }
                        .accessibilityIdentifier("subscribeButton")
                    } header: {
                        Text("見つかりました")
                    } footer: {
                        Text("あなたは見るだけで、書き換えることはできません。送り主が更新したら、ディレクトリのメニューから「最新を受け取る」で取り込めます。")
                    }
                }
            }
            .navigationTitle("IDで受け取る")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("やめる") { dismiss() }
                }
            }
            .alert("見つかりませんでした", isPresented: .constant(error != nil)) {
                Button("OK", role: .cancel) { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func lookUp() async {
        working = true
        defer { working = false }
        preview = nil
        do {
            let (id, pw) = try ShareCrypto.validate(id: shareID, password: password)
            preview = try await ShareClient.fetch(id: id, password: pw)
        } catch is ShareCrypto.ValidationError {
            error = "IDは3文字以上、パスワードは4文字以上の半角英数字です。"
        } catch let f as ShareClient.Failure {
            error = f.message
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func subscribe(_ doc: SharedDirectoryDocument) {
        guard let (id, pw) = try? ShareCrypto.validate(id: shareID, password: password) else { return }
        // 同じものを二度受け取ったら、増やさずに中身を入れ替える
        let dir: Directory
        if let existing = directories.first(where: { $0.isSubscribed && $0.shareID == id && $0.sharePassword == pw }) {
            dir = existing
        } else {
            let order = (directories.map(\.sortOrder).max() ?? 0) + 1
            dir = Directory(name: doc.name, sortOrder: order)
            dir.isSubscribed = true
            dir.shareID = id
            dir.sharePassword = pw
            context.insert(dir)
        }
        dir.name = doc.name
        dir.decimalMode = doc.decimalMode
        dir.lastFetchedAt = .now
        DirectoryStore.replaceGames(of: dir, with: doc.backup, in: context)
        dismiss()
    }
}
