import Foundation

/// 直前の状態に戻すための積み木。
///
/// 表を丸ごと覚える方式にしてある。`Session` は値型なので、差分を組むより
/// 単純で間違いが少ない。**巻き添えで別のマスが消える系の不具合**を過去に
/// 踏んでいるので、部分的に戻す仕組みは避けた。
///
/// 上限を決めているのは、長い対局で際限なく増やさないため。
public struct UndoStack<Value>: Sendable where Value: Sendable {
    public private(set) var entries: [Value] = []
    public let limit: Int

    public init(limit: Int = 30) {
        self.limit = max(1, limit)
    }

    public var canUndo: Bool { entries.isEmpty == false }
    public var count: Int { entries.count }

    /// 変更を加える**直前**に呼ぶ
    public mutating func push(_ value: Value) {
        entries.append(value)
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
    }

    /// 直前の状態を取り出す。何も無ければ nil
    public mutating func pop() -> Value? {
        entries.popLast()
    }

    public mutating func removeAll() {
        entries.removeAll()
    }
}
