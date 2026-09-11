import XCTest

/// 初回の「使い方」1枚。
///
/// 表示するかどうかは `didShowHowTo`（UserDefaults）で決まるので、
/// 起動引数で差し込んで両方の状態を作る（引き継ぎ書 11-10）。
final class HowToUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    /// 初回は自動で出て、伝えたい3つが全部書いてあること
    func testShowsOnFirstLaunch() {
        let app = launchApp(arguments: ["-didShowHowTo", "NO"])

        XCTAssertTrue(app.navigationBars["雀算の使い方"].waitForExistence(timeout: 20),
                      "初回に使い方が出ない")
        // 図と表に作り直したので、見出しで確かめる
        XCTAssertTrue(app.staticTexts["点数を入れる"].exists, "点数の説明が無い")
        XCTAssertTrue(app.staticTexts["上のボタン"].exists, "ボタンの説明が無い")
        XCTAssertTrue(app.staticTexts["三麻と四麻"].exists, "三麻の説明が無い")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "使い方-初回"
        shot.lifetime = .keepAlways
        add(shot)

        // 閉じたら表が触れること
        // テンキーにも「閉じる」があるので、バー側に限定する
        app.navigationBars["雀算の使い方"].buttons["閉じる"].tap()
        XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 10),
                      "閉じたあと本編に戻らない")
        XCTAssertFalse(app.navigationBars["雀算の使い方"].exists, "閉じても残っている")
    }

    /// 2回目以降は出ない
    func testDoesNotShowWhenAlreadySeen() {
        let app = launchApp(arguments: ["-didShowHowTo", "YES"])
        XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.navigationBars["雀算の使い方"].exists,
                       "2回目なのに使い方が出ている")
    }

    /// 読み飛ばしても、設定からいつでも開き直せること
    func testReachableFromSettings() {
        let app = launchApp(arguments: ["-didShowHowTo", "YES"])
        XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 20))
        app.buttons["openSettings"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 15))

        let howTo = app.buttons["showHowTo"]
        for _ in 0..<8 {
            if howTo.exists && howTo.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(howTo.exists && howTo.isHittable, "設定に「使い方」が無い")
        howTo.tap()

        XCTAssertTrue(app.navigationBars["雀算の使い方"].waitForExistence(timeout: 10),
                      "設定から使い方が開かない")
        XCTAssertTrue(app.staticTexts["点数を入れる"].exists)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "使い方-設定から"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
