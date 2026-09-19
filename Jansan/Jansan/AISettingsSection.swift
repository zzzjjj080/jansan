import SwiftUI

/// 設定の「AIで読み取る」。**鍵を入れなければ何も変わらない**（上級者向けの追加）
struct AISettingsSection: View {
    @State private var settings = AISettings.shared
    @State private var typing = ""
    @State private var checking = false
    @State private var result: String?
    @State private var failure: String?
    @State private var saved = 0

    var body: some View {
        Section {
            Picker("使うAI", selection: Binding(get: { settings.provider },
                                             set: { settings.provider = $0; typing = "" })) {
                ForEach(AIProvider.allCases) { provider in
                    Text(provider.name).tag(provider)
                }
            }
            .accessibilityIdentifier("aiProvider")

            HStack {
                SecureField(settings.hasKey ? "登録済み（入れ直すと差し替え）" : "APIキーを貼り付け", text: $typing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("aiKeyField")
                if settings.hasKey {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.accent)
                }
            }

            Button("この鍵を保存") { save() }
                .disabled(typing.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("saveAIKey")

            if settings.hasKey {
                Button {
                    check()
                } label: {
                    HStack {
                        Text("鍵が使えるか確かめる")
                        if checking { Spacer(); ProgressView() }
                    }
                }
                .disabled(checking)
                .accessibilityIdentifier("checkAIKey")

                Button("鍵を削除", role: .destructive) { remove() }
                    .accessibilityIdentifier("deleteAIKey")
            }

            LabeledContent("モデル") {
                TextField(settings.provider.defaultModel, text: Binding(get: { settings.model },
                                                                       set: { settings.model = $0 }))
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("aiModel")
            }

            if let result {
                Text(result).font(.footnote).foregroundStyle(Palette.accent)
            }
            if let failure {
                Text(failure).font(.footnote).foregroundStyle(Palette.negative)
            }
        } header: {
            Text("AIで読み取る")
        } footer: {
            Text("""
                ・入れなくても、写真の取り込みは端末の中の読み取りで使えます
                ・鍵を入れると、写真から取り込む画面に「AIに読ませる」が出ます。手書きの紙に強くなります
                ・鍵は\(settings.provider.keyPage)で作ります。料金はご自身の契約にかかります
                ・鍵はこの端末の中（キーチェーン）にだけ保存し、バックアップにも書き出しません
                ・写真がAIに送られるのは、その場で「AIに読ませる」を押したときだけです
                """)
        }
        .sensoryFeedback(.success, trigger: saved)
    }

    private func save() {
        do {
            try settings.setKey(typing)
            typing = ""
            saved += 1
            result = "鍵を保存しました。"
            failure = nil
        } catch {
            failure = error.localizedDescription
            result = nil
        }
    }

    private func remove() {
        do {
            try settings.setKey("")
            result = "鍵を削除しました。"
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }

    private func check() {
        guard let reader = settings.reader else { return }
        checking = true
        result = nil
        failure = nil
        Task {
            switch await reader.checkKey() {
            case .success(let model):
                result = "使えます（\(model)）"
            case .failure(let error):
                failure = error.message
            }
            checking = false
        }
    }
}
