import SwiftUI
import JansanCore

struct SettingsView: View {
    let board: ScoreBoard
    @Binding var showHistory: Bool
    @Binding var appTheme: AppTheme
    @Environment(\.dismiss) private var dismiss

    @State private var tipJar = TipJar()
    @State private var didSave = false
    @State private var limitAlert = false
    @State private var pendingDeletion: Roster.Member.ID?
    @State private var resetConfirm = false
    @State private var pendingDeactivation: Roster.Member.ID?

    var body: some View {
        NavigationStack {
            Form {
                newSessionSection
                membersSection
                presetsSection
                inputSection
                appearanceSection
                recordSection
                tipSection
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
                    if let id = pendingDeletion { board.removeMember(id: id) }
                    pendingDeletion = nil
                }
            } message: {
                if let id = pendingDeletion, let member = board.roster.member(id) {
                    Text("「\(member.name)」を名簿から完全に削除します。")
                }
            }
            .confirmationDialog("新規セッションにしますか", isPresented: $resetConfirm, titleVisibility: .visible) {
                Button("記録に残してから始める") {
                    board.archiveCurrentGame()
                    board.resetSession()
                }
                Button("記録に残さず始める", role: .destructive) {
                    board.resetSession()
                }
                Button("やめる", role: .cancel) {}
            } message: {
                Text("いまの表は消えます。あとで見返したい対局なら、残してから始めてください。")
            }
            .confirmationDialog(
                pendingDeactivation.flatMap { board.roster.member($0) }
                    .map { "「\($0.name)」を今回の参加から外しますか" } ?? "",
                isPresented: Binding(
                    get: { pendingDeactivation != nil },
                    set: { if !$0 { pendingDeactivation = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("外す（点数は消えます）", role: .destructive) {
                    if let id = pendingDeactivation { board.toggleActive(id: id) }
                    pendingDeactivation = nil
                }
                Button("やめる", role: .cancel) { pendingDeactivation = nil }
            } message: {
                Text("この人には入力済みの点数があります。外すと表から列ごと消えます。")
            }
        }
    }

    // MARK: - メンバー

    private var membersSection: some View {
        Section {
            // 添字ではなくメンバーそのものを回す。
            // 添字だと、削除で件数が減った直後に古い添字のまま再描画が走って落ちる
            ForEach(board.roster.members) { member in
                memberRow(member)
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

    private func memberRow(_ member: Roster.Member) -> some View {
        HStack(spacing: 12) {
            Button {
                // 入力済みの人を外すと点数ごと消えるので、そのときだけ確認する
                if member.isActive, board.hasEntries(id: member.id) {
                    pendingDeactivation = member.id
                } else if !board.toggleActive(id: member.id) {
                    limitAlert = true
                }
            } label: {
                Image(systemName: member.isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(member.isActive ? Palette.accent : Palette.inkDim)
            }
            .buttonStyle(.plain)

            TextField("名前", text: Binding(
                // 値そのものを使う。ここで配列を引き直すと削除直後に落ちる
                get: { member.name },
                set: { board.rename(id: member.id, to: $0) }
            ))

            Button {
                pendingDeletion = member.id
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

    private var recordSection: some View {
        Section {
            Button {
                board.archiveCurrentGame()
                didSave = true
                Task {
                    try? await Task.sleep(for: .seconds(1.8))
                    didSave = false
                }
            } label: {
                Label(
                    didSave ? "保存しました" : "この対局を記録に残す",
                    systemImage: didSave ? "checkmark.circle.fill" : "square.and.arrow.down"
                )
                .foregroundStyle(didSave ? Palette.accent : Color.accentColor)
            }

            Button("保存した記録を見る") {
                dismiss()
                showHistory = true
            }
        } header: {
            Text("記録")
        } footer: {
            Text("入力中の内容は自動で保存されるので、アプリを閉じても続きから再開できます。ここで残す「記録」は別枠で、後から振り返りたい対局を日付付きで取っておくためのものです。")
        }
    }

    private var newSessionSection: some View {
        Section {
            Button {
                resetConfirm = true
            } label: {
                Label("新規セッションにする", systemImage: "arrow.clockwise")
            }
        } footer: {
            Text("いまの対局を終えて、次の半荘を始めるときに使います。")
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker("表示", selection: $appTheme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.label).tag(theme)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("見た目")
        } footer: {
            Text("「端末に合わせる」はiPhoneのライト/ダーク設定に従います。暗い場所で打つときはダーク固定が読みやすいことがあります。")
        }
    }

    // MARK: - カンパ

    private var tipSection: some View {
        Section {
            switch tipJar.state {
            case .unavailable:
                Text("いまは受け付けられません")
                    .foregroundStyle(Palette.inkDim)
            case .thanks:
                Label("ありがとうございます", systemImage: "heart.fill")
                    .foregroundStyle(Palette.negative)
            default:
                Button {
                    Task { await tipJar.tip() }
                } label: {
                    HStack {
                        Label("開発者にカンパする", systemImage: "cup.and.saucer.fill")
                        Spacer()
                        if tipJar.state == .purchasing {
                            ProgressView()
                        } else if let price = tipJar.displayPrice {
                            Text(price).foregroundStyle(Palette.inkDim)
                        }
                    }
                }
                .disabled(tipJar.product == nil || tipJar.state == .purchasing)
            }
        } header: {
            Text("応援")
        } footer: {
            Text("雀算は無料で、広告もありません。気が向いたときだけで大丈夫です。送っていただいても機能は変わりません。")
        }
        .task { await tipJar.load() }
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
