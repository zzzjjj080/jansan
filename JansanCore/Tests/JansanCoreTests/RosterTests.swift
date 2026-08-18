import Testing
@testable import JansanCore

@Suite("名簿")
struct RosterTests {

    private func sample() -> Roster {
        Roster(names: ["中村", "五十嵐", "斎藤", "佐々木", "石井", "小野寺"], activeCount: 4)
    }

    @Test("参加中のメンバーだけが表の列になる")
    func activeNamesAreColumns() {
        #expect(sample().activeNames == ["中村", "五十嵐", "斎藤", "佐々木"])
    }

    @Test("6人を超えて参加させられない")
    func respectsMaxActive() {
        var roster = Roster(names: ["A", "B", "C", "D", "E", "F", "G"], activeCount: 6)
        #expect(roster.toggleActive(at: 6) == false)
        #expect(roster.activeCount == 6)
    }

    @Test("最後の1人は参加から外せない")
    func keepsAtLeastOneActive() {
        var roster = Roster(names: ["A", "B"], activeCount: 1)
        #expect(roster.toggleActive(at: 0) == false)
        #expect(roster.activeCount == 1)
    }

    @Test("参加していないメンバーも名簿からは消えない")
    func inactiveMembersRemain() {
        var roster = sample()
        roster.toggleActive(at: 0)
        #expect(roster.activeNames == ["五十嵐", "斎藤", "佐々木"])
        #expect(roster.members.count == 6)
    }


    @Test("名前を空にするとプレースホルダが入る")
    func renameNeverEmpties() {
        var roster = sample()
        roster.rename(at: 0, to: "")
        #expect(roster.members[0].name == "名前")
    }

    @Test("名簿の変更が表の列に反映され、残る人の入力は保たれる")
    func syncsIntoSession() {
        var roster = sample()
        var session = Session(players: roster.activeNames)
        session.enter(-32, at: Position(round: 0, column: 0))
        session.enter(71, at: Position(round: 0, column: 1))

        // 4人目のチェックを外して3人にする
        roster.toggleActive(id: roster.members[3].id)
        session.setPlayers(roster.activeNames)

        #expect(session.players == ["中村", "五十嵐", "斎藤"])
        #expect(session.rounds[0].entries[0] == .entered(-32))
        #expect(session.rounds[0].entries[1] == .entered(71))
    }

    // 画面側は添字ではなくIDでメンバーを指す。
    // 添字だと、削除で件数が減った直後に古い添字のまま再描画が走り、
    // 配列の範囲外アクセスでアプリが落ちる(実際に落ちた)。

    @Test("IDで指定して削除できる")
    func removesByID() {
        var roster = sample()
        let target = roster.members[0].id

        roster.remove(id: target)
        #expect(roster.members.count == 5)
        #expect(roster.index(of: target) == nil)
        #expect(roster.members.first?.name == "五十嵐")
    }

    @Test("削除済みのIDを指しても何も起きない")
    func staleIDIsIgnored() {
        var roster = sample()
        let target = roster.members[0].id
        roster.remove(id: target)
        let before = roster.members

        // 消えたIDに対する操作は、落ちずに無視される
        roster.remove(id: target)
        roster.rename(id: target, to: "誰か")
        let changed = roster.toggleActive(id: target)
        #expect(changed == false)
        #expect(roster.member(target) == nil)
        #expect(roster.members == before)
    }

    @Test("IDで名前と参加状態を変えられる")
    func editsByID() {
        var roster = sample()
        let target = roster.members[1].id

        roster.rename(id: target, to: "五十嵐さん")
        #expect(roster.member(target)?.name == "五十嵐さん")

        let deactivated = roster.toggleActive(id: target)
        #expect(deactivated)
        #expect(roster.member(target)?.isActive == false)
    }
}
