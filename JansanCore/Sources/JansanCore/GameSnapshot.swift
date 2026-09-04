import Foundation

/// 1回の対局を復元するのに必要な状態一式。
///
/// **アプリ側ではなく Core に置いている。** バックアップの読み書きと
/// 横断集計がこれを使うため、テストから触れる場所に無いと確かめられない。
/// JSONにはこの型の名前は出ないので、置き場所を変えても保存済みのデータは読める。
public struct GameSnapshot: Codable, Equatable, Sendable {
    public var roster: Roster
    public var session: Session
    public var autoConfirm: Bool

    public init(roster: Roster, session: Session, autoConfirm: Bool) {
        self.roster = roster
        self.session = session
        self.autoConfirm = autoConfirm
    }
}
