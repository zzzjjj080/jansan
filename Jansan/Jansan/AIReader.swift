import Foundation
import UIKit
import JansanCore

/// 写真を AI に読ませて、取り込める形（CSV）にしてもらう。
///
/// **鍵は利用者自身のもの。** 料金も利用者の契約に乗る。鍵が無ければこの道は出さず、
/// 端末の中の読み取り（`TextInPhoto`）だけで使える。写真を送るのは、利用者がその場で押したときだけ
enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case claude
    case chatgpt

    var id: String { rawValue }

    var name: String {
        switch self {
        case .claude: "Claude（Anthropic）"
        case .chatgpt: "ChatGPT（OpenAI）"
        }
    }

    /// 鍵を作る場所。設定画面に出して、そこまで案内する
    var keyPage: String {
        switch self {
        case .claude: "console.anthropic.com"
        case .chatgpt: "platform.openai.com"
        }
    }

    /// 既定のモデル。新しいものが出たら設定で変えられる
    var defaultModel: String {
        switch self {
        case .claude: "claude-sonnet-5"
        case .chatgpt: "gpt-5"
        }
    }

    var endpoint: URL {
        switch self {
        case .claude: URL(string: "https://api.anthropic.com/v1/messages")!
        case .chatgpt: URL(string: "https://api.openai.com/v1/chat/completions")!
        }
    }

    func modelPage(_ model: String) -> URL {
        switch self {
        case .claude: URL(string: "https://api.anthropic.com/v1/models/\(model)")!
        case .chatgpt: URL(string: "https://api.openai.com/v1/models/\(model)")!
        }
    }
}

struct AIReader {
    let provider: AIProvider
    let key: String
    let model: String

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// 写真を送って CSV をもらう
    func readCSV(from image: UIImage) async throws -> String {
        guard let jpeg = image.jpegData(compressionQuality: 0.7) else {
            throw Failure(message: "写真を送れる形にできませんでした。")
        }
        var request = URLRequest(url: provider.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers() { request.setValue(value, forHTTPHeaderField: field) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body(base64: jpeg.base64EncodedString()))

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard status == 200 else {
            throw Failure(message: "AIが読み取れませんでした（\(status)）。\(Self.errorMessage(object))")
        }
        let text = Self.text(from: object, provider: provider)
        guard !text.isEmpty else { throw Failure(message: "AIからの返事が空でした。") }
        return Self.csvPart(of: text)
    }

    /// 鍵が使えるかだけを確かめる。モデルの情報を読むだけなので料金はかからない
    func checkKey() async -> Result<String, Failure> {
        var request = URLRequest(url: provider.modelPage(model))
        request.timeoutInterval = 30
        for (field, value) in headers() { request.setValue(value, forHTTPHeaderField: field) }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            guard status == 200 else {
                return .failure(Failure(message: "使えませんでした（\(status)）。\(Self.errorMessage(object))"))
            }
            return .success(model)
        } catch {
            return .failure(Failure(message: "通信できませんでした。\(error.localizedDescription)"))
        }
    }

    // MARK: - 組み立て（テストから確かめる）

    func headers() -> [String: String] {
        switch provider {
        case .claude:
            ["x-api-key": key, "anthropic-version": "2023-06-01"]
        case .chatgpt:
            ["Authorization": "Bearer \(key)"]
        }
    }

    func body(base64: String) -> [String: Any] {
        switch provider {
        case .claude:
            [
                "model": model,
                "max_tokens": 4000,
                "messages": [[
                    "role": "user",
                    "content": [
                        ["type": "image",
                         "source": ["type": "base64", "media_type": "image/jpeg", "data": base64]],
                        ["type": "text", "text": AIReader.prompt],
                    ],
                ]],
            ]
        case .chatgpt:
            [
                "model": model,
                "messages": [[
                    "role": "user",
                    "content": [
                        ["type": "text", "text": AIReader.prompt],
                        ["type": "image_url",
                         "image_url": ["url": "data:image/jpeg;base64,\(base64)"]],
                    ],
                ]],
            ]
        }
    }

    /// 送るお願い文。**画面からコピーできるものと同じ**にする（結果が食い違わないように）
    static var prompt: String {
        CSVImport.aiPrompt + "\n\n返事はCSVだけにしてください。説明文や記号の囲みは付けないでください。"
    }

    // MARK: - 返事の取り出し

    static func text(from object: [String: Any]?, provider: AIProvider) -> String {
        guard let object else { return "" }
        switch provider {
        case .claude:
            let blocks = object["content"] as? [[String: Any]] ?? []
            return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
        case .chatgpt:
            let choices = object["choices"] as? [[String: Any]] ?? []
            let message = choices.first?["message"] as? [String: Any]
            if let text = message?["content"] as? String { return text }
            // 新しい形では content が配列で返ることがある
            let parts = message?["content"] as? [[String: Any]] ?? []
            return parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
    }

    /// 返事から CSV の部分だけを取る。**囲みの記号が付いてくることがある**
    static func csvPart(of text: String) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let start = lines.firstIndex(where: { $0.hasPrefix("```") }) {
            let rest = lines[(start + 1)...]
            let end = rest.firstIndex(where: { $0.hasPrefix("```") }) ?? lines.endIndex
            lines = Array(lines[(start + 1)..<end])
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func errorMessage(_ object: [String: Any]?) -> String {
        guard let error = object?["error"] as? [String: Any] else { return "" }
        return (error["message"] as? String) ?? ""
    }
}
