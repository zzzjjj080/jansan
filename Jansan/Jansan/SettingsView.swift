import SwiftUI
import JansanCore

struct SettingsView: View {
    let board: ScoreBoard
    @Environment(\.dismiss) private var dismiss

    @State private var limitAlert = false
    @State private var pendingDeletion: Int?
    @State private var resetConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                membersSection
                presetsSection
                inputSection
                dangerSection
#if DEBUG
                debugSection
#endif
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }.bold()
                }
            }
            .alert("参加できるのは最大\(Roster.maxActive)人までです", isPresented: $limitAlert) {
                Button("OK", role: .cancel) {}
            }
            .alert("この操作は元に戻せません", isPresented: .constant(pendingDeletion != nil)) {
                Button("キャンセル", role: .cancel) { pendingDeletion = nil }
                Button("削除", role: .destructive) {
                    if let index = pendingDeletion { board.removeMember(at: index) }
                    pendingDeletion = nil
                }
            } message: {
                if let index = pendingDeletion, board.roster.members.indices.contains(index) {
                    Text("「\(board.roster.members[index].name)」を名簿から完全に削除します。")
                }
            }
            .alert("新規セッションにしますか", isPresented: $resetConfirm) {
                Button("キャンセル", role: .cancel) {}
                Button("リセット", role: .destructive) { board.resetSession() }
            } message: {
                Text("現在の入力内容はすべて消えます。")
            }
        }
    }

    // MARK: - メンバー

    private var membersSection: some View {
        Section {
            ForEach(board.roster.members.indices, id: \.self) { index in
                memberRow(index)
            }
            Button {
                board.addMember()
            } label: {
                Label("新しいメンバーを登録", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("参加メンバー（\(board.roster.activeCount)人）")
        } footer: {
            Text("チェックが「今回参加」で、そのまま表の列になります。外したメンバーも名簿には残ります。5〜6人のときは、3人分入力したあと実際に打った4人目をタップすると自動で確定します。")
        }
    }

    private func memberRow(_ index: Int) -> some View {
        HStack(spacing: 12) {
            Button {
                if !board.toggleActive(at: index) { limitAlert = true }
            } label: {
                Image(systemName: board.roster.members[index].isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(board.roster.members[index].isActive ? Palette.accent : Palette.inkDim)
            }
            .buttonStyle(.plain)

            TextField("名前", text: Binding(
                get: { board.roster.members[index].name },
                set: { board.rename(at: index, to: $0) }
            ))

            Button {
                pendingDeletion = index
            } label: {
                Image(systemName: "trash").foregroundStyle(Palette.negative)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - プリセット

    private var presetsSection: some View {
        Section("モードプリセット") {
            Picker("人数", selection: Binding(
                get: { board.roster.activeCount },
                set: { board.applyPreset(activeCount: $0) }
            )) {
                Text("三人打ち").tag(3)
                Text("四人打ち").tag(4)
                Text("五人").tag(5)
                Text("六人").tag(6)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - 入力

    private var inputSection: some View {
        Section {
            Toggle("小数点モード", isOn: Binding(
                get: { board.decimalMode },
                set: { board.decimalMode = $0 }
            ))
            Toggle("自動確定モード", isOn: Binding(
                get: { board.autoConfirm },
                set: { board.autoConfirm = $0 }
            ))
        } header: {
            Text("入力設定")
        } footer: {
            Text("小数点モードは末尾1桁を小数として扱います（323 と打つと 32.3）。自動確定をOFFにすると、桁数によらず「確定」を押すまで待ちます。")
        }
    }

    private var dangerSection: some View {
        Section {
            Button("新規セッションにする", role: .destructive) { resetConfirm = true }
        }
    }

#if DEBUG
    private var debugSection: some View {
        Section {
            Button("デモデータを12局入れる") {
                board.seedDemoRounds(12)
                dismiss()
            }
            Button("デモデータを30局入れる") {
                board.seedDemoRounds(30)
                dismiss()
            }
        } header: {
            Text("開発用")
        } footer: {
            Text("行数が増えたときの自動縮小を確認するためのものです。リリースビルドには含まれません。")
        }
    }
#endif
}
