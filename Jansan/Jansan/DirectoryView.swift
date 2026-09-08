import SwiftUI
import SwiftData
import JansanCore

/// ディレクトリ1つの中身。記録の一覧と、集計・画像・共有への入口。
struct DirectoryView: View {
    @Bindable var directory: Directory
    let board: ScoreBoard
    var goToInput: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("currentDirectory") private var currentDirectoryID = Directory.defaultUID.uuidString

    @State private var showStats = false
    @State private var showShare = false
    @State private var showRename = false
    @State private var deleteConfirm = false
    @State private var renameText = ""
    @State private var refreshing = false
    @State private var refreshError: String?
    /// 自動取得はこの画面に入ったとき1回だけ。開くたびに毎回は走らせない
    @State private var didAutoRefresh = false

    private var isCurrent: Bool { directory.uid.uuidString == currentDirectoryID }

    var body: some View {
        HistoryView(board: board, directory: directory, goToInput: goToInput)
            // 受け取ったディレクトリは、開いたら黙って最新を取りに行く。
            // 手で「最新を受け取る」を押さないと更新されないのは、
            // 押すことを知らない人には「壊れている」としか見えない
            .task {
                guard directory.isSubscribed, !didAutoRefresh else { return }
                didAutoRefresh = true
                await refresh(silent: true)
            }
            .refreshable {
                if directory.isSubscribed { await refresh(silent: true) }
            }
            .overlay(alignment: .top) {
                if refreshing {
                    Label("最新を受け取っています…", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.bar, in: Capsule())
                        .padding(.top, 6)
                }
            }
            .navigationTitle(directory.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showStats = true
                    } label: {
                        Label("集計", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    .accessibilityIdentifier("directoryStats")

                    Menu {
                        if directory.isEditable {
                            Button {
                                currentDirectoryID = directory.uid.uuidString
                            } label: {
                                Label(isCurrent ? "保存先になっています" : "ここを保存先にする",
                                      systemImage: isCurrent ? "checkmark.circle.fill" : "tray.and.arrow.down")
                            }
                            .disabled(isCurrent)
                            .accessibilityIdentifier("makeCurrent")

                            Button {
                                showShare = true
                            } label: {
                                Label(directory.isShared ? "共有の設定" : "共有する",
                                      systemImage: "antenna.radiowaves.left.and.right")
                            }
                            .accessibilityIdentifier("shareSettings")

                            Button {
                                renameText = directory.name
                                showRename = true
                            } label: {
                                Label("名前を変える", systemImage: "pencil")
                            }
                            .disabled(directory.isDefault)
                        } else {
                            Button {
                                Task { await refresh() }
                            } label: {
                                Label(refreshing ? "受け取っています…" : "いま最新を受け取る", systemImage: "arrow.clockwise")
                            }
                            .disabled(refreshing)
                            .accessibilityIdentifier("refreshSubscription")
                        }

                        if !directory.isDefault {
                            Divider()
                            Button(role: .destructive) {
                                deleteConfirm = true
                            } label: {
                                Label(directory.isSubscribed ? "受け取るのをやめる" : "ディレクトリを削除",
                                      systemImage: "trash")
                            }
                            .accessibilityIdentifier("deleteDirectory")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("directoryMenu")
                }
            }
            .sheet(isPresented: $showStats) {
                AllStatsView(directory: directory)
            }
            .sheet(isPresented: $showShare) {
                ShareSettingsView(directory: directory)
            }
            .alert("名前を変える", isPresented: $showRename) {
                TextField("名前", text: $renameText)
                Button("保存") {
                    let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        directory.name = name
                        directory.updatedAt = .now
                        if directory.isShared { directory.needsPublish = true }
                        try? context.save()
                    }
                }
                Button("やめる", role: .cancel) {}
            }
            .alert(directory.isSubscribed ? "受け取るのをやめますか" : "このディレクトリを削除しますか",
                   isPresented: $deleteConfirm) {
                Button("やめる", role: .cancel) {}
                Button(directory.isSubscribed ? "やめる（記録も消す）" : "削除する", role: .destructive) {
                    delete()
                }
            } message: {
                Text(directory.isSubscribed
                     ? "この端末に取り込んだぶんは消えます。送り主の記録には影響しません。また同じIDとパスワードで受け取れます。"
                     : "中の記録 \(DirectoryStore.gameCount(of: directory, in: context)) 件も一緒に消えます。元に戻せません。共有中なら、公開されたものも消します。")
            }
            .alert("受け取れませんでした", isPresented: .constant(refreshError != nil)) {
                Button("OK", role: .cancel) { refreshError = nil }
            } message: {
                Text(refreshError ?? "")
            }
    }

    /// - Parameter silent: 自動での取得。失敗を画面に出さない
    ///   （電波が無いだけのことが多く、開くたびに叱られるのは煩わしい）
    private func refresh(silent: Bool = false) async {
        refreshing = true
        defer { refreshing = false }
        do {
            let doc = try await ShareClient.fetch(id: directory.shareID, password: directory.sharePassword)
            directory.name = doc.name
            directory.decimalMode = doc.decimalMode
            directory.lastFetchedAt = .now
            DirectoryStore.replaceGames(of: directory, with: doc.backup, in: context)
        } catch let failure as ShareClient.Failure {
            if !silent { refreshError = failure.message }
        } catch {
            if !silent { refreshError = error.localizedDescription }
        }
    }

    private func delete() {
        // 共有中なら公開されたものも消す。失敗しても手元は消す（残しても意味がない）
        if directory.isShared {
            let id = directory.shareID, pw = directory.sharePassword
            Task { try? await ShareClient.unpublish(id: id, password: pw) }
        }
        for game in DirectoryStore.games(of: directory, in: context) { context.delete(game) }
        if isCurrent { currentDirectoryID = Directory.defaultUID.uuidString }
        context.delete(directory)
        try? context.save()
        dismiss()
    }
}
