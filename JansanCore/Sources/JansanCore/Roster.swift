import Foundation

/// 登録済みメンバーの名簿。
///
/// 「今回参加していない人」も消えないのが要点。参加(active)なメンバーが表の列になり、
/// 参加者を入れ替えても Session.setPlayers が名前を手がかりに入力を引き継ぐ。
public struct Roster: Equatable, Sendable, Codable {
    /// 表の列として扱える上限
    public static let maxActive = 6

    public struct Member: Identifiable, Equatable, Sendable, Codable {
        public var id: UUID
        public var name: String
        public var isActive: Bool

        public init(id: UUID = UUID(), name: String, isActive: Bool) {
            self.id = id
            self.name = name
            self.isActive = isActive
        }
    }

    public private(set) var members: [Member]

    public init(members: [Member]) {
        self.members = members
    }

    public init(names: [String], activeCount: Int) {
        self.members = names.enumerated().map { index, name in
            Member(name: name, isActive: index < activeCount)
        }
    }

    public var activeNames: [String] {
        members.filter(\.isActive).map(\.name)
    }

    public var activeCount: Int {
        members.filter(\.isActive).count
    }

    // MARK: - ID指定の操作

    /// 画面側は添字ではなくIDで指すこと。
    /// SwiftUIのForEachに添字を渡すと、削除で件数が減った直後に
    /// 古い添字のまま再描画が走り、配列の範囲外アクセスで落ちる。
    public func index(of id: Member.ID) -> Int? {
        members.firstIndex { $0.id == id }
    }

    public func member(_ id: Member.ID) -> Member? {
        index(of: id).map { members[$0] }
    }

    public mutating func rename(id: Member.ID, to name: String) {
        guard let index = index(of: id) else { return }
        rename(at: index, to: name)
    }

    @discardableResult
    public mutating func toggleActive(id: Member.ID) -> Bool {
        guard let index = index(of: id) else { return false }
        return toggleActive(at: index)
    }

    public mutating func remove(id: Member.ID) {
        guard let index = index(of: id) else { return }
        remove(at: index)
    }

    // MARK: - 編集

    public mutating func rename(at index: Int, to name: String) {
        guard members.indices.contains(index) else { return }
        // 空欄のままだと列見出しが消えてしまうので、最低限のプレースホルダを入れておく
        members[index].name = name.isEmpty ? "名前" : name
    }

    /// 参加状態を切り替える。上限に達している場合は何もせず false を返す
    @discardableResult
    public mutating func toggleActive(at index: Int) -> Bool {
        guard members.indices.contains(index) else { return false }
        if members[index].isActive {
            // 全員未参加になると表の列が無くなるので、最後の1人は外せない
            guard activeCount > 1 else { return false }
            members[index].isActive = false
            return true
        }
        guard activeCount < Self.maxActive else { return false }
        members[index].isActive = true
        return true
    }

    public mutating func add(name: String) {
        members.append(Member(name: name, isActive: activeCount < Self.maxActive))
    }

    public mutating func remove(at index: Int) {
        guard members.indices.contains(index) else { return }
        members.remove(at: index)
    }

}
