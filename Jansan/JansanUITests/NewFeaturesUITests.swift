import XCTest

/// 1.3 で足した機能を、実際にタップして確かめる。
///
/// 記録が要るテストは、デバッグ用の「デモデータ」で表を作ってから
/// 入力画面の保存ボタンで保存して用意する。
final class NewFeaturesUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-didShowHowTo", "YES"] + arguments
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func openSettings(_ app: XCUIApplication) {
        let gear = app.buttons["openSettings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 20), "設定ボタンが無い")
        gear.tap()
        // 起動直後の1回目は飲まれることがある。効かなければ1回だけ押し直す
        if !app.navigationBars["設定"].waitForExistence(timeout: 8) { gear.tap() }
        if !app.navigationBars["設定"].waitForExistence(timeout: 15) {
            attach(app, "NG-設定が開かない")
            let d = XCTAttachment(string: "hittable=\(gear.isHittable) frame=\(gear.frame)\n" + app.debugDescription)
            d.name = "NG-設定が開かないときの要素"; d.lifetime = .keepAlways; add(d)
            XCTFail("設定が開かない")
        }
    }

    private func scrollToBottom(_ app: XCUIApplication, times: Int = 8) {
        for _ in 0..<times { app.swipeUp() }
    }

    /// 目当ての要素が押せるようになるまで送る。
    /// 設定は項目が増えて縦に長くなったので、固定回数のスワイプでは届かない
    @discardableResult
    private func scrollTo(_ app: XCUIApplication, _ element: XCUIElement, tries: Int = 10) -> Bool {
        for _ in 0..<tries {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    /// デモデータを入れて記録として保存する。集計や検索の材料を作る
    private func makeRecords(_ app: XCUIApplication, count: Int = 2) {
        useDefaultDirectory(app)
        for _ in 0..<count {
            openSettings(app)
            let seed = app.buttons["デモデータを3局入れる"]
            XCTAssertTrue(scrollTo(app, seed), "デモデータのボタンが無い（Debugビルドで走らせること）")
            seed.tap()

            // 保存は入力画面の右上。押すと確認が1枚挟まる
            tapSave(app)
        }
    }

    /// 保存先を「マイ記録」に戻す。
    /// **@AppStorage は起動をまたいで残る。** 前のテストが保存先を変えたままだと、
    /// 次のテストが別のディレクトリへ保存して「記録が無い」と誤検知する
    private func useDefaultDirectory(_ app: XCUIApplication) {
        let picker = app.buttons["pickDirectory"]
        XCTAssertTrue(picker.waitForExistence(timeout: 20), "保存先のボタンが無い")
        picker.tap()
        XCTAssertTrue(app.navigationBars["保存先"].waitForExistence(timeout: 10), "保存先の選択が開かない")
        let mine = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'マイ記録'")).firstMatch
        XCTAssertTrue(mine.waitForExistence(timeout: 10), "「マイ記録」が選べない")
        mine.tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS '保存先: マイ記録'"))
                        .firstMatch.waitForExistence(timeout: 10), "保存先がマイ記録にならない")
    }

    /// 保存ボタンを押して、確認まで通す
    private func tapSave(_ app: XCUIApplication) {
        let save = app.buttons["saveGame"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "保存ボタンが無い")
        save.tap()
        // **アラートの中に限定する。** 単に label CONTAINS 'に残す' で探すと、
        // ツールバーの保存ボタン自身（読み上げ名「この対局を記録に残す」）に当たって
        // 保存されないまま通ってしまう
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "保存の確認が出ない")
        let confirm = alert.buttons.matching(NSPredicate(format: "label ENDSWITH 'に残す'")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "確認のボタンが無い")
        confirm.tap()
        XCTAssertFalse(alert.waitForExistence(timeout: 3), "確認が閉じていない")
    }

    /// 記録タブを開いて「マイ記録」に入る
    private func openMyRecords(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 20), "入力画面が出ない")
        app.segmentedControls.firstMatch.buttons["記録"].tap()
        let mine = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'マイ記録'")).firstMatch
        XCTAssertTrue(mine.waitForExistence(timeout: 10), "「マイ記録」が無い")
        mine.tap()
        XCTAssertTrue(app.navigationBars["マイ記録"].waitForExistence(timeout: 10), "マイ記録が開かない")
    }

    // MARK: - 記録の検索・編集

    func testSearchAndEditRecord() {
        let app = launchApp()
        makeRecords(app, count: 1)

        openMyRecords(app)

        // 行をタップすると閲覧専用の画面が開く（入力の表は置き換わらない）
        let firstRow = app.buttons.matching(NSPredicate(format: "label CONTAINS '人打ち'")).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 10), "記録の行が無い")
        firstRow.tap()
        XCTAssertTrue(app.staticTexts["保存した記録・見るだけ"].waitForExistence(timeout: 10),
                      "見るだけの帯が出ていない")
        attach(app, "記録を見る")
        app.buttons["閉じる"].firstMatch.tap()

        // 日付とメモを編集
        let edit = app.buttons["日付とメモを編集"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 10), "編集ボタンが無い")
        edit.tap()

        XCTAssertTrue(app.navigationBars["記録を編集"].waitForExistence(timeout: 10), "編集画面が開かない")
        let note = app.textFields["noteField"]
        XCTAssertTrue(note.waitForExistence(timeout: 10), "メモ欄が無い")
        note.tap()
        note.typeText("田中宅")
        attach(app, "記録の編集")
        app.buttons["保存"].tap()

        // メモが一覧に出る
        XCTAssertTrue(app.staticTexts["田中宅"].waitForExistence(timeout: 10), "メモが一覧に出ない")

        // そのメモで検索できる
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "検索欄が無い")
        field.tap()
        field.typeText("田中宅")
        XCTAssertTrue(app.staticTexts["田中宅"].waitForExistence(timeout: 10), "検索しても出てこない")
        attach(app, "検索")

        // 当たらない語では消える
        field.buttons.firstMatch.tap()
        field.typeText("該当しない語")
        XCTAssertFalse(app.staticTexts["田中宅"].waitForExistence(timeout: 3), "絞り込めていない")
    }

    // MARK: - 横断集計

    func testAllStatsAggregatesSavedGames() {
        let app = launchApp()
        makeRecords(app, count: 2)

        // 集計はディレクトリごとに見る。入力中の表だけのグラフは置いていない
        openMyRecords(app)
        app.buttons["directoryStats"].tap()
        XCTAssertTrue(app.navigationBars.matching(
            NSPredicate(format: "identifier CONTAINS 'の集計'")).firstMatch.waitForExistence(timeout: 15),
            "ディレクトリの集計が開かない")

        // 少なくとも今作った2対局は集計されている。
        // 「全記録」は他のディレクトリも合算するので、前のテストが残した分が上乗せされうる
        let summary = app.staticTexts.matching(NSPredicate(format: "label MATCHES '^[0-9]+ 対局.*'")).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 10), "対局数が出ていない")
        let count = Int(summary.label.split(separator: " ").first ?? "") ?? 0
        XCTAssertGreaterThanOrEqual(count, 2, "対局数が足りない: \(summary.label)")
        XCTAssertTrue(app.buttons["periodPicker"].waitForExistence(timeout: 5)
                      || app.segmentedControls.firstMatch.exists, "期間の切り替えが無い")
        attach(app, "全記録のビュー")
    }

    // MARK: - バックアップ

    func testBackupExportAndRejectCSV() {
        let app = launchApp()
        makeRecords(app, count: 1)

        openSettings(app)
        let backup = app.buttons["showBackup"]
        XCTAssertTrue(scrollTo(app, backup), "バックアップの導線が無い")
        backup.tap()
        XCTAssertTrue(app.navigationBars["バックアップ"].waitForExistence(timeout: 15), "バックアップが開かない")

        let copy = app.buttons["copyBackup"]
        XCTAssertTrue(copy.waitForExistence(timeout: 10), "コピーのボタンが無い")
        XCTAssertTrue(copy.isEnabled, "記録があるのにコピーできない")
        copy.tap()
        XCTAssertTrue(app.staticTexts["コピーしました"].waitForExistence(timeout: 10), "コピーの手応えが出ない")
        attach(app, "バックアップ")

        // CSVを貼ったら、CSVでは戻せないと言うこと
        let field = app.textViews["backupPasteField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "貼り付け欄が無い")
        field.tap()
        field.typeText("局,中村,五十嵐\n1,30,10\n")
        app.buttons["previewImport"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10), "何も言われない")
        XCTAssertTrue(app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS 'CSV'")).firstMatch.exists,
            "CSVでは戻せないことが伝わっていない")
        attach(app, "CSVを貼ったとき")
    }

    // MARK: - すべてのデータの削除

    func testEraseAllRemovesRecords() {
        let app = launchApp()
        makeRecords(app, count: 1)

        openSettings(app)
        let erase = app.buttons["eraseAll"]
        XCTAssertTrue(scrollTo(app, erase), "削除の導線が無い")
        erase.tap()

        XCTAssertTrue(app.alerts["すべてのデータを消しますか"].waitForExistence(timeout: 10), "確認が出ない")
        // バックアップを促していること
        XCTAssertTrue(app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS 'バックアップ'")).firstMatch.exists,
            "消す前にバックアップを促していない")
        app.alerts.buttons["すべて消す"].tap()
        XCTAssertTrue(app.alerts["消しました"].waitForExistence(timeout: 10), "完了が出ない")
        app.alerts.buttons["OK"].tap()

        // 履歴が空になっている
        openMyRecords(app)
        XCTAssertTrue(app.staticTexts["まだ記録がありません"].waitForExistence(timeout: 15), "記録が残っている")
        attach(app, "削除後")
    }
}

// MARK: - 一括スクショ

extension NewFeaturesUITests {

    /// 3枚の画像が作られ、共有と保存の導線が出ること
    func testShareImagesMakesThreePictures() {
        let app = launchApp()
        makeRecords(app, count: 2)

        openMyRecords(app)
        app.buttons["directoryStats"].tap()
        XCTAssertTrue(app.navigationBars.matching(
            NSPredicate(format: "identifier CONTAINS 'の集計'")).firstMatch.waitForExistence(timeout: 15),
            "ディレクトリの集計が開かない")

        let make = app.buttons["makeImages"]
        XCTAssertTrue(make.waitForExistence(timeout: 10), "画像の導線が無い")
        make.tap()

        XCTAssertTrue(app.navigationBars["画像で送る"].waitForExistence(timeout: 20), "画像の画面が開かない")
        XCTAssertTrue(app.buttons["shareImages"].waitForExistence(timeout: 20), "共有の導線が無い")
        XCTAssertTrue(app.buttons["saveToPhotos"].exists, "写真に保存の導線が無い")

        // 3枚できていること。ボタンのアイコンも images に入るので、識別子で数える
        for index in 0..<3 {
            XCTAssertTrue(app.images["sharePreview\(index)"].waitForExistence(timeout: 15),
                          "\(index + 1)枚目ができていない")
        }
        XCTAssertFalse(app.images["sharePreview3"].exists, "4枚目ができている")
        attach(app, "画像で送る")

        app.swipeUp()
        attach(app, "画像で送る-2枚目以降")
    }
}
