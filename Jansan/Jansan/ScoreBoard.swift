import Foundation
import Observation
import UIKit
import JansanCore

/// 画面の状態。計算そのものはJansanCoreのSessionが持ち、ここは
/// 「今どのマスを選んでいるか」「入力途中の数字は何か」だけを管理する。
@MainActor
@Observable
final class ScoreBoard {
    private(set) var session: Session
    private(set) var selection: Position?
    private(set) var buffer = ""
    private(set) var isNegative = false

    /// OFFにすると桁数による自動確定をせず、「確定」を押すまで待つ
    var autoConfirm = true
    var isKeypadVisible = true

    private var confirmTask: Task<Void, Never>?

    init(players: [String]) {
        session = Session(players: players)
    }

    var decimalMode: Bool {
        get { session.decimalMode }
        set { session.decimalMode = newValue }
    }

    /// 入力途中の数字。確定前でも表のマスに薄く表示する
    var pendingValue: Int? {
        guard let magnitude = Int(buffer) else { return nil }
        return isNegative ? -magnitude : magnitude
    }

    /// テンキー上部の表示。打ち始める前は選択中の人の名前を出す
    var keypadCaption: String {
        guard let selection else { return "タップして入力" }
        guard let pendingValue else { return session.players[selection.column] }
        return ScoreFormatter.string(pendingValue, decimalMode: decimalMode)
    }

    var isCaptionPlaceholder: Bool { selection == nil }

    // MARK: - マスの操作

    func tap(_ position: Position) {
        // 入力途中に別のマスをタップしたら、今の内容を先に確定してから移動する
        if let selection, !buffer.isEmpty, selection != position {
            commit()
        }
        if session.canDesignateWinner(at: position) {
            session.designateWinner(at: position)
            haptic()
            advance(from: position)
        } else {
            select(position)
        }
    }

    func select(_ position: Position) {
        selection = position
        clearBuffer()
        isKeypadVisible = true
    }

    // MARK: - テンキー

    func press(digit: String) {
        guard selection != nil else { return }
        // 小数点モードは末尾1桁が小数部になる分、1桁多く打てる
        let maxLength = decimalMode ? 4 : 3
        let settleLength = decimalMode ? 3 : 2
        guard buffer.count < maxLength else { return }

        buffer.append(digit)
        haptic()
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
        haptic()
    }

    func pressBackspace() {
        guard selection != nil, !buffer.isEmpty else { return }
        confirmTask?.cancel()
        buffer.removeLast()
        haptic()
    }

    func pressRest() {
        guard let position = selection else { return }
        session.toggleResting(at: position)
        haptic()
        advance(from: position)
    }

    func commit() {
        guard let position = selection, let value = pendingValue else { return }
        confirmTask?.cancel()
        session.enter(value, at: position)
        haptic()

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

    // MARK: - 内部

    private func advance(from position: Position) {
        if let next = session.nextOpenPosition(after: position) {
            select(next)
        } else {
            deselect()
        }
    }

    /// 入力完了後もテンキーは開いたままにして、選択状態だけ解除する
    private func deselect() {
        selection = nil
        clearBuffer()
    }

    private func clearBuffer() {
        confirmTask?.cancel()
        buffer = ""
        isNegative = false
    }

    /// Web版のVibration APIはiOSで動かなかったが、実機アプリではこれが正解
    private func haptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
