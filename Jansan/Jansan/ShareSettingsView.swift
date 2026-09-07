import SwiftUI
import SwiftData
import JansanCore

/// 自分のディレクトリを共有する設定。ID とパスワードを決めて公開する。
///
/// パスワードは短くてよい。レコード名にパスワードが要る作りなので、
/// 知らない人は辿り着けない（→ ShareCrypto）。
struct ShareSettingsView: View {
    @Bindable var directory: Directory
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var shareID = ""
    @State private var password = ""
    @State private var working = false
    @State private var error: String?
    @State private var didPublish = false
    @State private var stopConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                if directory.isShared {
                    sharedSection
                } else {
                    setupSection
                }
            }
            .navigationTitle("共有")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .alert("できませんでした", isPresented: .constant(error != nil)) {
                Button("OK", role: .cancel) { error = nil }
            } message: {
                Text(error ?? "")
            }
            .confirmationDialog("共有をやめますか", isPresented: $stopConfirm, titleVisibility: .visible) {
                Button("共有をやめる", role: .destructive) { Task { await stop() } }
                Button("やめない", role: .cancel) {}
            } message: {
                Text("受け取っている人は、それ以降の更新を見られなくなります。すでに取り込んだぶんは相手の端末に残ります。")
            }
        }
        .onAppear {
            shareID = directory.shareID
            password = directory.sharePassword
        }
    }

    // MARK: - 共有前

    private var setupSection: some View {
        Group {
            Section {
                TextField("ID（3〜20文字）", text: $shareID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .accessibilityIdentifier("shareIDField")
                TextField("パスワード（4〜20文字）", text: $password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .accessibilityIdentifier("sharePasswordField")
            } header: {
                Text("IDとパスワード")
            } footer: {
                Text("半角の英数字だけ。大文字と小文字は区別しません。口で伝えやすいものにしてください。\n\n受け取る人は「記録」タブの ＋ →「IDで受け取る」で、この2つを入れます。")
            }

            Section {
                Button {
                    Task { await publish() }
                } label: {
                    HStack {
                        Label(working ? "公開しています…" : "この内容で共有する", systemImage: "antenna.radiowaves.left.and.right")
                        if working { Spacer(); ProgressView() }
                    }
                }
                .disabled(working || shareID.isEmpty || password.isEmpty)
                .accessibilityIdentifier("publishButton")
            } footer: {
                Text("「\(directory.name)」の記録 \(DirectoryStore.gameCount(of: directory, in: context)) 件を、IDとパスワードを知っている人が見られるようになります。相手は見るだけで、書き換えることはできません。\n\n以後は記録を保存するたびに自動で送られます。")
            }
        }
    }

    // MARK: - 共有中

    private var sharedSection: some View {
        Group {
            Section {
                LabeledContent("ID", value: directory.shareID)
                LabeledContent("パスワード", value: directory.sharePassword)
            } header: {
                Text("受け取る人に伝えるもの")
            } footer: {
                Text("受け取る人は「記録」タブの ＋ →「IDで受け取る」で、この2つを入れます。")
            }

            Section {
                if let at = directory.lastPublishedAt {
                    LabeledContent("最後に送った", value: at.formatted(.dateTime.month().day().hour().minute().locale(Locale(identifier: "ja_JP"))))
                }
                if directory.needsPublish {
                    Label("まだ送っていない変更があります", systemImage: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(Palette.negative)
                }
                Button {
                    Task { await publish() }
                } label: {
                    HStack {
                        Label(working ? "送っています…" : (didPublish ? "送りました" : "いま送る"),
                              systemImage: didPublish ? "checkmark.circle.fill" : "arrow.up.circle")
                        if working { Spacer(); ProgressView() }
                    }
                }
                .disabled(working)
                .accessibilityIdentifier("republishButton")
            } header: {
                Text("送信")
            } footer: {
                Text("記録を保存するたびに自動で送られます。届いていないと言われたら、ここから送り直してください。")
            }

            Section {
                Button("共有をやめる", role: .destructive) { stopConfirm = true }
                    .accessibilityIdentifier("stopSharing")
            }
        }
    }

    // MARK: - 動作

    private func publish() async {
        working = true
        defer { working = false }
        do {
            let (id, pw) = try ShareCrypto.validate(id: shareID, password: password)
            if directory.ownerToken.isEmpty { directory.ownerToken = UUID().uuidString }
            let doc = DirectoryStore.document(of: directory, in: context)
            try await ShareClient.publish(doc, id: id, password: pw, ownerToken: directory.ownerToken)
            directory.isShared = true
            directory.shareID = id
            directory.sharePassword = pw
            directory.lastPublishedAt = .now
            directory.needsPublish = false
            try? context.save()
            didPublish = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                didPublish = false
            }
        } catch let v as ShareCrypto.ValidationError {
            error = message(for: v)
        } catch let f as ShareClient.Failure {
            error = f.message
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func stop() async {
        working = true
        defer { working = false }
        try? await ShareClient.unpublish(id: directory.shareID, password: directory.sharePassword)
        directory.isShared = false
        directory.needsPublish = false
        directory.lastPublishedAt = nil
        try? context.save()
        dismiss()
    }

    private func message(for error: ShareCrypto.ValidationError) -> String {
        switch error {
        case .idTooShort: "IDは3文字以上にしてください（半角英数字のみ）。"
        case .idTooLong: "IDは20文字までです。"
        case .passwordTooShort: "パスワードは4文字以上にしてください（半角英数字のみ）。"
        case .passwordTooLong: "パスワードは20文字までです。"
        }
    }
}
