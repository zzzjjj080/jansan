import Foundation
import Observation
import SwiftData
import UIKit
import JansanCore

/// 画面の状態。計算そのものはJansanCoreのSessionが持ち、ここは
/// 「今どのマスを選んでいるか」「入力途中の数字は何か」だけを管理する。
@MainActor
@Observable
final class ScoreBoard {
    private(set) var session: Session
    private(set) var roster: Roster
    private(set) var selection: Position?
    private(set) var buffer = ""
    private(set) var isNegative = false

    /// OFFにすると桁数による自動確定をせず、「確定」を押すまで待つ
    var autoConfirm = true {
        didSet { scheduleDraftSave() }
    }
    /// テンキーの開閉は画面の状態なので保存しない
    var isKeypadVisible = true

    private let haptics = Haptics()
    private var confirmTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var context: ModelContext?

    init(roster: Roster) {
        self.roster = roster
        session = Session(players: roster.activeNames)
    }

    // MARK: - 保存

    /// 起動時に一度だけ呼ぶ。前回の続きがあれば復元する
    func attach(context: ModelContext) {
        guard self.context == nil else { return }
        self.context = context
        restoreDraft()
    }

    private var snapshot: GameSnapshot {
        GameSnapshot(roster: roster, session: session, autoConfirm: autoConfirm)
    }

    private func restoreDraft() {
        guard let draft = fetchDraft(), let restored = try? draft.snapshot() else { return }
        guard !restored.roster.activeNames.isEmpty else { return }
        roster = restored.roster
        session = restored.session
        autoConfirm = restored.autoConfirm
        deselect()
    }

    private func fetchDraft() -> SavedGame? {
        let descriptor = FetchDescriptor<SavedGame>(predicate: #Predicate { $0.isDraft })
        return try? context?.fetch(descriptor).first
    }

    /// 1マス打つたびに書きに行かないよう、少しまとめてから保存する
    func scheduleDraftSave() {
        guard context != nil else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveDraft()
        }
    }

    private func saveDraft() {
        guard let context else { return }
        let current = snapshot
        do {
            if let draft = fetchDraft() {
                draft.savedAt = .now
                draft.playerNames = current.session.players
                draft.totals = current.session.totals
                draft.roundCount = current.session.playedRoundCount
                draft.decimalMode = current.session.decimalMode
                draft.payload = try JSONEncoder().encode(current)
            } else {
                context.insert(try SavedGame(snapshot: current, isDraft: true))
            }
            try context.save()
        } catch {
            // 保存に失敗しても入力は続けられるようにする
            print("下書きの保存に失敗: \(error)")
        }
    }

    /// 「保存」で記録として残す。作業中の下書きとは別枠で積まれる
    func archiveCurrentGame() {
        guard let context else { return }
        do {
            context.insert(try SavedGame(snapshot: snapshot, isDraft: false))
            try context.save()
        } catch {
            print("記録の保存に失敗: \(error)")
        }
    }

    func load(_ game: SavedGame) {
        guard let restored = try? game.snapshot(), !restored.roster.activeNames.isEmpty else { return }
        roster = restored.roster
        session = restored.session
        autoConfirm = restored.autoConfirm
        deselect()
        scheduleDraftSave()
    }

    var decimalMode: Bool {
        get { session.decimalMode }
        set {
            session.decimalMode = newValue
            scheduleDraftSave()
        }
    }

    /// 入力途中の数字。確定前でも表のマスに薄く表示する
    var pendingValue: Int? {
        guard let magnitude = Int(buffer) else { return nil }
        return isNegative ? -magnitude : magnitude
    }

    /// テンキー上部の表示。打ち始める前は選択中の人の名前を出すが、
    /// マイナスを押した時点で数字側の表示に切り替える
    var keypadCaption: String {
        guard let selection else { return "タップして入力" }
        if let pendingValue {
            return ScoreFormatter.string(pendingValue, decimalMode: decimalMode)
        }
        if isNegative { return "−" }
        return session.players[selection.column]
    }

    var isCaptionPlaceholder: Bool { selection == nil }

    /// マイナス入力中はキャプションもマスのプレビューも赤で出す
    var isEnteringNegative: Bool { selection != nil && isNegative }

    // MARK: - マスの操作

    func tap(_ position: Position) {
        // 入力途中に別のマスをタップしたら、今の内容を先に確定してから移動する
        if let selection, !buffer.isEmpty, selection != position {
            commit()
        }
        if session.canDesignateWinner(at: position) {
            session.designateWinner(at: position)
            haptics.confirm()
            advance(from: position)
        } else {
            select(position)
        }
    }

    func select(_ position: Position) {
        selection = position
        clearBuffer()
        isKeypadVisible = true
        // 打ち始める直前に温めておくと、1打目から取りこぼさない
        haptics.warmUp()
    }

    // MARK: - テンキー

    func press(digit: String) {
        guard selection != nil else { return }
        // 小数点モードは末尾1桁が小数部になる分、1桁多く打てる
        let maxLength = decimalMode ? 4 : 3
        let settleLength = decimalMode ? 3 : 2
        guard buffer.count < maxLength else { return }

        buffer.append(digit)
        haptics.tap()
        confirmTask?.cancel()
        guard autoConfirm else { return }

        if buffer.count == maxLength {
            commit()
        } else if buffer.count == settleLength {
            // もう1桁来るかもしれないので少しだけ待つ
            confirmTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                self?.commit()
            }
        }
    }

    func pressMinus() {
        guard selection != nil else { return }
        isNegative.toggle()
        haptics.tap()
    }

    func pressBackspace() {
        guard selection != nil, !buffer.isEmpty else { return }
        confirmTask?.cancel()
        buffer.removeLast()
        haptics.tap()
    }

    func pressRest() {
        guard let position = selection else { return }
        session.toggleResting(at: position)
        haptics.confirm()
        advance(from: position)
    }

    func commit() {
        guard let position = selection, let value = pendingValue else { return }
        confirmTask?.cancel()
        session.enter(value, at: position)
        haptics.confirm()

        // 5〜6人打ちで誰が4人目か未確定のときだけ、タップでの指定を待つ
        if session.needsWinnerDesignation(at: position.round) {
            deselect()
        } else {
            advance(from: position)
        }
    }

    func closeKeypad() {
        isKeypadVisible = false
        deselect()
    }

    // MARK: - 名簿

    func rename(at index: Int, to name: String) {
        roster.rename(at: index, to: name)
        syncPlayers()
    }

    /// 上限や最後の1人の制約で切り替えられなかった場合は false
    @discardableResult
    func toggleActive(at index: Int) -> Bool {
        let changed = roster.toggleActive(at: index)
        if changed { syncPlayers() }
        return changed
    }

    func addMember() {
        roster.add(name: "プレイヤー\(roster.members.count + 1)")
        syncPlayers()
    }

    func removeMember(at index: Int) {
        roster.remove(at: index)
        syncPlayers()
    }

    func applyPreset(activeCount: Int) {
        roster.applyPreset(activeCount: activeCount)
        syncPlayers()
    }

    /// 表の行そのものを消す。入れ間違えた局の取り消し用
    func removeRound(at index: Int) {
        session.removeRound(at: index)
        haptics.confirm()
        deselect()
    }

    func resetSession() {
        session.reset()
        deselect()
    }

    /// 名簿を変えたら列を組み直す。選択中のマスは位置がずれるので解除する
    private func syncPlayers() {
        guard !roster.activeNames.isEmpty else { return }
        session.setPlayers(roster.activeNames)
        deselect()
    }

    // MARK: - 内部

    // 盤面が動く経路はすべてこの2つのどちらかを通るので、保存のフックはここに置く
    private func advance(from position: Position) {
        if let next = session.nextOpenPosition(after: position) {
            select(next)
            scheduleDraftSave()
        } else {
            deselect()
        }
    }

    /// 入力完了後もテンキーは開いたままにして、選択状態だけ解除する
    private func deselect() {
        selection = nil
        clearBuffer()
        scheduleDraftSave()
    }

    private func clearBuffer() {
        confirmTask?.cancel()
        buffer = ""
        isNegative = false
    }

    /// Web版のVibration APIはiOSで動かなかったが、実機アプリではこれが正解。
    /// 強さの使い分けは Haptics 側に持たせている

#if DEBUG
    /// レイアウト検証用。行数と人数が増えたときに表が1画面へ収まるかを確かめるために使う。
    /// リリースビルドには含まれない
    func seedDemoRounds(_ count: Int) {
        let samples = [
            [-32, 71, -50], [51, -52, 15], [15, -32, 61], [9, -51, 53],
            [5, 43, -15], [-53, 56, -16], [-23, 67, 20], [-18, -22, 55],
        ]
        let playerCount = session.players.count
        for round in 0..<count {
            let scores = samples[round % samples.count]
            // 5人以上のときは打つ4人を毎局ずらす。同じ人がずっとお休みだと
            // 実際の卓の様子と違ううえ、見た目でも列が死んで見える
            let seats = (0..<4).map { (round + $0) % playerCount }
            for (index, score) in scores.enumerated() {
                session.enter(score, at: Position(round: round, column: seats[index]))
            }
            if session.needsWinnerDesignation(at: round) {
                session.designateWinner(at: Position(round: round, column: seats[3]))
            }
        }
        deselect()
    }
#endif
}
