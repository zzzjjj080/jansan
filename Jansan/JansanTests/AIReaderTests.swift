import Testing
import Foundation
@testable import Jansan

/// AI へ送る形と、返事の取り出し。**通信はしない**（組み立てと読み取りだけを固定する）
struct AIReaderTests {

    private func reader(_ provider: AIProvider) -> AIReader {
        AIReader(provider: provider, key: "sk-test", model: "test-model")
    }

    @Test("Claude は x-api-key と版、ChatGPT は Bearer で送る")
    func headers() {
        #expect(reader(.claude).headers()["x-api-key"] == "sk-test")
        #expect(reader(.claude).headers()["anthropic-version"] == "2023-06-01")
        #expect(reader(.chatgpt).headers()["Authorization"] == "Bearer sk-test")
    }

    @Test("写真とお願い文が、それぞれの形で入る")
    func body() throws {
        let claude = reader(.claude).body(base64: "AAAA")
        #expect(claude["model"] as? String == "test-model")
        let content = try #require(((claude["messages"] as? [[String: Any]])?.first?["content"]) as? [[String: Any]])
        let source = try #require(content.first?["source"] as? [String: Any])
        #expect(source["data"] as? String == "AAAA")
        #expect(source["media_type"] as? String == "image/jpeg")

        let gpt = reader(.chatgpt).body(base64: "AAAA")
        let parts = try #require(((gpt["messages"] as? [[String: Any]])?.first?["content"]) as? [[String: Any]])
        let url = try #require(parts.last?["image_url"] as? [String: Any])
        #expect((url["url"] as? String)?.hasPrefix("data:image/jpeg;base64,AAAA") == true)
        // 送る本文は、画面からコピーできるお願い文と同じものを使う
        #expect((parts.first?["text"] as? String)?.contains("CSV") == true)
    }

    @Test("返事から本文を取り出す（どちらの形でも）")
    func text() {
        let claude: [String: Any] = ["content": [["type": "text", "text": "A,B\n1,-1"]]]
        #expect(AIReader.text(from: claude, provider: .claude) == "A,B\n1,-1")

        let gpt: [String: Any] = ["choices": [["message": ["content": "A,B\n1,-1"]]]]
        #expect(AIReader.text(from: gpt, provider: .chatgpt) == "A,B\n1,-1")

        let gptParts: [String: Any] = ["choices": [["message": ["content": [["type": "text", "text": "A,B"]]]]]]
        #expect(AIReader.text(from: gptParts, provider: .chatgpt) == "A,B")
        #expect(AIReader.text(from: nil, provider: .claude).isEmpty)
    }

    @Test("囲みの記号が付いてきても、CSV の中身だけ取る")
    func csvPart() {
        let fenced = """
        こちらが結果です。
        ```csv
        中村,五十嵐,斎藤,佐々木
        30,10,-10,-30
        ```
        """
        #expect(AIReader.csvPart(of: fenced) == "中村,五十嵐,斎藤,佐々木\n30,10,-10,-30")
        #expect(AIReader.csvPart(of: "A,B\n1,-1") == "A,B\n1,-1")
    }

    @Test("断られたときは、向こうの言い分を出す")
    func errorMessage() {
        let object: [String: Any] = ["error": ["message": "invalid x-api-key"]]
        #expect(AIReader.errorMessage(object) == "invalid x-api-key")
        #expect(AIReader.errorMessage(nil).isEmpty)
    }
}
