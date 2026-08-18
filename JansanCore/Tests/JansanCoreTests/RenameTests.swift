import Testing
@testable import JansanCore

/// setPlayers は名前をキーに列を対応付ける。
/// そのため改名に setPlayers を使うと「別人が現れた」と解釈され、
/// その人の点数が丸ごと消える（実際に消えた）。改名は renamePlayer を使う。
@Suite("改名")
struct RenameTests {

    private func played() -> Session {
        var session = Session(players: ["中村", "五十嵐", "斎藤", "佐々木"])
        session.enter(-32, at: Position(round: 0, column: 0))
        session.enter(71, at: Position(round: 0, column: 1))
        session.enter(-50, at: Position(round: 0, column: 2))
        return session
    }

    @Test("名前を変えても点数は残る")
    func keepsScores() {
        var session = played()
        session.renamePlayer(at: 0, to: "中村さん")

        #expect(session.players == ["中村さん", "五十嵐", "斎藤", "佐々木"])
        #expect(session.rounds[0].entries[0] == .entered(-32))
        #expect(session.rounds[0].entries[3] == .derived(11))
        #expect(session.totals == [-32, 71, -50, 11])
    }

    @Test("1文字ずつ打ち替えても点数は残る")
    func survivesIncrementalTyping() {
        var session = played()
        // 入力欄は1文字ごとに反映されるので、その連打に耐える必要がある
        for name in ["中", "中村", "中村X", "中村XY"] {
            session.renamePlayer(at: 0, to: name)
        }
        #expect(session.players[0] == "中村XY")
        #expect(session.rounds[0].entries[0] == .entered(-32))
        #expect(session.totals == [-32, 71, -50, 11])
    }

    @Test("範囲外の列を指定しても何も起きない")
    func ignoresBadColumn() {
        var session = played()
        let before = session
        session.renamePlayer(at: 9, to: "誰か")
        #expect(session == before)
    }

    @Test("setPlayers を改名に使うと点数が消える（renamePlayerが必要な理由）")
    func setPlayersLosesScoresOnRename() {
        var session = played()
        session.setPlayers(["中村X", "五十嵐", "斎藤", "佐々木"])

        // 「中村」が居なくなり「中村X」が現れた、と解釈されるため空になる
        #expect(session.rounds[0].entries[0] == .empty)
    }
}
