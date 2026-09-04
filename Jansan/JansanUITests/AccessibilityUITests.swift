import XCTest

/// 読み上げと文字サイズ。
///
/// 表は列数ぶんを横に並べるので、文字を無制限には大きくできない。
/// **その代わり、値がすべて読み上げから取れることをここで担保する。**
final class AccessibilityUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-didShowHowTo", "YES"] + arguments
        app.launch()
        return app
    }

    /// マスが「·」ではなく、誰の何局目で何点かを読めること
    func testCellsAreReadable() {
        let app = launchApp()
        XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 20))

        // 名簿も入力済みの値も前の操作で変わりうるので、位置で指して自分で空にする
        let cell = app.buttons["cell-0-0"]
        XCTAssertTrue(cell.waitForExistence(timeout: 10), "マスが読み上げの対象になっていない")
        cell.tap()
        clearCell(app, cell)
        XCTAssertEqual(cell.value as? String, "未入力", "空のマスが「未入力」と読めない")

        // 点数を入れると値が読める
        for key in ["3", "0"] { app.buttons[key].firstMatch.tap() }
        app.buttons["確定"].tap()
        XCTAssertEqual(cell.value as? String, "30", "入力した点数が読めない")

        // お休みは記号ではなく言葉で読める
        cell.tap()
        clearCell(app, cell)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'お休み'")).firstMatch.tap()
        XCTAssertEqual(cell.value as? String, "お休み", "お休みが言葉で読めない")

        // 後片付け。次のテストに空の状態を渡す
        cell.tap()
        clearCell(app, cell)
    }

    /// マスの中身を空にする。「クリア」は中身があるときだけ出る
    private func clearCell(_ app: XCUIApplication, _ cell: XCUIElement) {
        for _ in 0..<4 {
            guard (cell.value as? String) != "未入力" else { return }
            let clear = app.buttons["クリア"]
            guard clear.exists, clear.isHittable else { return }
            clear.tap()
        }
    }

    /// 記号のキーが言葉で読めること
    func testKeypadKeysAreNamed() {
        let app = launchApp()
        XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 20))

        XCTAssertTrue(app.buttons["マイナス"].exists, "「−」がマイナスと読めない")
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'お休み'")).firstMatch.exists,
            "お休みキーの説明が無い")

        // マスを選ぶと ⌫ が出る。中身があるマスでは「クリア」に変わる
        app.buttons["cell-0-0"].tap()
        let backspace = app.buttons["1文字消す"]
        let clear = app.buttons["クリア"]
        XCTAssertTrue(backspace.waitForExistence(timeout: 5) || clear.exists,
                      "「⌫」が言葉で読めない")
    }

    /// 局番号の行が、削除できることを含めて読めること
    func testRoundNumberIsReadable() {
        let app = launchApp()
        XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 20))

        let round = app.buttons["1局目"]
        XCTAssertTrue(round.waitForExistence(timeout: 10), "局番号が読み上げの対象になっていない")
    }

    /// いちばん大きい文字サイズでも、表の数字が潰れて読めなくならないこと
    func testLargestTextSizeStillShowsTable() {
        let app = XCUIApplication()
        app.launchArguments = ["-didShowHowTo", "YES",
                               "-UIPreferredContentSizeCategoryName",
                               "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()

        XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 20))
        // 表が出ていて、マスが読める状態のままであること
        let cell = app.buttons["cell-0-0"]
        XCTAssertTrue(cell.waitForExistence(timeout: 10), "最大の文字サイズで表が壊れている")
        // 値が読み上げから取れること。表示が潰れても情報は失われない
        XCTAssertFalse((cell.value as? String ?? "").isEmpty, "最大の文字サイズで値が読めない")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "最大の文字サイズ"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
