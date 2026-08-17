# iPhoneアプリ開発・リリース 引き継ぎ書

麻雀スコア記録アプリ「雀算」を、HTMLプロトタイプから **App Store審査提出まで** 一通りやり切った記録。
**次のiPhoneアプリを作るとき、このファイル全体を新しいClaude Codeのチャットに貼る**ことを想定してまとめている。

アプリ固有の話ではなく「次も必ず使う知識」を中心に書いた。
**特に「実際に踏んだ罠」と「リリース手続き」の章は必ず読むこと。** 知らないと同じ時間を溶かす。

---

## 0. 新しいチャットでの切り出し方

このファイル全体を貼ったうえで、こう書けばよい。

> 前回iPhoneアプリを1本作ってApp Store提出まで終えたときの引き継ぎ書です。
> これを踏まえて、今回は「日記アプリ」を作りたい。
> まず要件を整理してから、同じ進め方で始めてください。

---

## 1. 開発環境（このMacの現状）

| 項目 | 状態 |
|---|---|
| Mac | Apple Silicon / macOS 26 |
| Xcode | 26.6 |
| Swift | 6.3 |
| Apple Developer Program | **登録済み**（個人・年$99） |
| **Team ID** | `A7WA598R44` |
| Apple ID（開発者） | zzzjjj080@yahoo.co.jp |
| GitHub | `zzzjjj080` / SSH鍵設定済み（パスフレーズなし） |
| git identity | jin / zzzjjj080@gmail.com |
| 実機 | iPhone 15（チームに登録済み・デベロッパモード有効） |
| Homebrew / gh | **入っていない** |

Claude Codeの権限は `~/.claude/settings.json` で Bash・Read・Edit・Write・Glob・Grep を全許可済み。
毎回の許可プロンプトは出ない。

**Developer Program も実機登録も済んでいるので、2本目は1本目よりずっと速い。**

---

## 2. 進め方（この順番を推奨）

### ① HTMLで動くプロトタイプを作る

Swiftを書く前に、ブラウザで動くHTML1枚で操作感を作り込む。これが非常に効いた。

- 仕様の迷いをSwift移植前に潰せる
- 修正が数秒で反映される
- 画面を見ながら議論できる

雀算ではこの段階で60項目以上の調整を済ませ、**Swift移植後の手戻りはほぼゼロ**だった。

### ② ロジックだけ先にSwift Packageへ（UI抜き）

`○○Core` というUI非依存のSwift Packageを作り、計算・判定ロジックだけ移してテストを書く。

- Xcodeを待たずに `swift test` で進められる
- 一番壊れやすい部分がテストで固定される
- UIを何度作り直しても、ロジックの無事を1秒で確認できる
- 雀算では最終的にテスト45本になり、リファクタが怖くなくなった

**型でバグを防ぐ設計にする。** 状態はBool複数ではなくenumで表す。

```swift
enum Entry {
    case empty          // 入力待ち
    case resting        // 不参加
    case entered(Int)   // 手入力
    case derived(Int)   // 自動計算
}
```

「手入力なのに不参加」のようなあり得ない組み合わせを作れなくなる。

### ③ UIを載せる

`@Observable`（iOS 17+）で状態クラスを1つ。Viewはそれを見るだけ。
`ObservableObject` + `@Published` は不要。

### ④ シミュレータで実際に触って確認する

Claude Codeからシミュレータを操作できる。
**「ビルドが通った」で終わらせず、必ずタップさせて確認すること。** これで実際に何度もバグが見つかった。

### ⑤ 実機で確認する

シミュレータでは分からないものがある。**触覚フィードバック（バイブ）は実機でしか確認できない。**

---

## 3. Xcodeプロジェクト作成時にやること

新規作成した直後に**必ず**以下を確認・変更する。デフォルトのままだと事故る。

### 作成ダイアログ

| 項目 | 設定 |
|---|---|
| Organization Identifier | `com.zzzjjj080` |
| Testing System | **Swift Testing** |
| Storage | **None**（SwiftDataは自分で設計してから入れる） |
| Create Git repository | **チェックを外す**（リポジトリはルート側で作る） |

### 作成直後のビルド設定（ここが最重要）

```
IPHONEOS_DEPLOYMENT_TARGET = 26.5  →  18.0
```

**Xcodeは最新OSを初期値にする。** そのままだと最新OSの端末にしか入らず、ほぼ誰にも届かない。
iOS 18なら SwiftData / @Observable / Swift Charts / ContentUnavailableView / Color.mix が全部使える。

```
TARGETED_DEVICE_FAMILY = "1,2,7"  →  1
```

初期値はiPhone+iPad+Vision。**iPhoneのみに絞る**とレイアウトもスクリーンショットも楽になる。

```
developmentRegion = en  →  ja      （knownRegions に ja を追加）
```

日本語アプリなら必須。これをやらないと**スワイプ削除が「Delete」**のまま英語で出る。
`ja` にするだけでシステム由来のUIが全部日本語になる。

```
INFOPLIST_KEY_CFBundleDisplayName = "アプリ名"
INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait
DEVELOPMENT_TEAM = A7WA598R44
```

---

## 4. 実際に踏んだ罠

### 4-1. Command Line Toolsだけでは `swift test` が動かない

XCTestもSwift TestingもXcode.appに同梱。CLTだけだとテストが走らない。

### 4-2. `xcode-select -p` は当てにならない

Xcodeを入れても「明示的に選択していない」状態がある。`xcode-select -p` はフォールバックで正しいパスを返すのでビルドは通るが、シミュレータ連携などは動かない。

本当の確認はこれ。

```bash
ls -l /var/db/xcode_select_link   # 無ければ未選択
```

未選択なら**ユーザー自身がターミナルで**実行する（sudoなのでClaudeからは不可）。

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

### 4-3. シミュレータを複数起動すると入力が別端末に飛ぶ

使わない方は落とす。`xcrun simctl shutdown "iPhone 17"` / `xcrun simctl list devices booted` で確認。
また `install` の前に `boot` が要る。`Unable to lookup in current state: Shutdown` はこれ。

### 4-4. macOSに `timeout` コマンドは無い

GNU coreutils。使うと終了コード127で「実行されていない」のに気づかず時間を溶かす。

### 4-5. `#if DEBUG` が効いているかは実物で確認する

```bash
xcodebuild -configuration Release ... build
strings path/to/App.app/App | grep "デモデータ"   # 何も出なければOK
```

### 4-6. テスト用ファイルがアプリに同梱されることがある

`.storekit` をプロジェクト管理下（同期フォルダ内）に置いたら、**リリースビルドのapp内に入ってしまった**。

```bash
find path/to/App.app -name "*.storekit"   # 何も出ないこと
```

`.xcscheme` に手書きでStoreKit設定のパスを書くのは基準が不明瞭で3回外した。
**Xcodeの Edit Scheme → Run → Options から設定させる**のが確実。

### 4-7. 機能を足したら既存の説明文の整合性を確認する

雀算では「インターネットに接続しません」とプライバシーポリシー・サポートページ・ストア掲載文・READMEの
**4か所**に書いていた。あとから課金（StoreKit）を入れて**全部が嘘になった**。
虚偽のプライバシー表示は審査で問題になる典型。

### 4-8. 自動計算と手動クリアは相性が悪い

「1マス消す」と「残りから自動で埋める」を同時に走らせると、
消したマスが即座に埋め直されたり、自動で入っていた別のマスが巻き添えで消えたりする。

**消す操作は消すだけにして、再計算は次に値が確定したときへ回す。**
「選び直したら再計算」も試したが、巻き添えが遅れて起きるだけで解決しなかった。

### 4-9. 個人登録だと本名がApp Storeに公開される

販売者名として本名が出る。屋号にはできない。**登録前に納得しておくこと。**

### 4-10. EU配信にはトレーダーステータス（住所公開）が必要

デジタルサービス法により、EU配信には氏名・住所・電話の公開が要る。
**日本のみに配信地域を限定すれば不要。** あとから地域を広げるのは審査なしでできる。

---

## 5. リリース手続き（ここが一番ハマった）

**順番が重要。** 飛ばすと後で詰まる。

### ① Xcodeにアカウントを追加

Xcode → Settings → Accounts → ＋ → Apple ID。
証明書はこの後のアーカイブ時にXcodeが自動で作る。

### ② Team ID をビルド設定に入れる

Team IDは [developer.apple.com/account](https://developer.apple.com/account) の **Membership details** にある英数字10文字。
App Store Connect に出ている数字（例: 1070981569）とは**別物**。

```
DEVELOPMENT_TEAM = A7WA598R44
```

### ③ 【重要】Explicit な App ID を先に登録する

**Xcodeの自動署名はワイルドカード（`TEAMID.*`）のApp IDを作る。**
これだと **App Store Connect のバンドルID選択肢が空のまま**になり、アプリを登録できない。

[developer.apple.com/account/resources/identifiers/list](https://developer.apple.com/account/resources/identifiers/list)
→ ＋ → App IDs → App → **Bundle IDは Explicit を選択** → `com.zzzjjj080.アプリ名`

確認方法（アーカイブ後）:

```bash
security cms -D -i App.app/embedded.mobileprovision > p.plist
/usr/libexec/PlistBuddy -c "Print Entitlements:application-identifier" p.plist
# TEAMID.* ならワイルドカード（NG）
# TEAMID.com.zzzjjj080.App なら正しい
```

### ④ 実機を1台チームに登録する

**アーカイブには開発用プロファイルが要り、その作成にはチームへの実機登録が1台以上必要。**
未登録だとこのエラーで止まる。

```
Your team has no devices from which to generate a provisioning profile.
```

**iPhoneをUSBで繋ぎ、Xcodeから一度実行するのが一番早い**（登録・デベロッパモードの案内・実機確認が同時に済む）。
デベロッパモードは**Macに繋いでXcodeが認識したあとに初めて設定に出てくる**。最初は見当たらなくて正常。

### ⑤ アーカイブと書き出し

```bash
xcodebuild -project App.xcodeproj -scheme App -configuration Release \
  -destination 'generic/platform=iOS' -archivePath /tmp/App.xcarchive \
  -allowProvisioningUpdates archive
```

アーカイブがワイルドカードで署名されていても問題ない。**配布用の署名は書き出し時に付け直される。**

ExportOptions.plist:

```xml
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>A7WA598R44</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>destination</key><string>export</string>   <!-- upload にすると直接アップロード -->
</dict>
```

```bash
xcodebuild -exportArchive -archivePath /tmp/App.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath /tmp/export \
  -allowProvisioningUpdates
```

**`destination` を `upload` にすれば、Xcodeにサインイン済みのアカウントでそのままアップロードできる。**
app-specific password も API キーも要らない。`Upload succeeded` が出れば成功。

### ⑥ App Store Connect でアプリを登録

**アプリ登録は「Explicit App ID の登録後」でないとバンドルIDが選べない。**
ページを開きっぱなしなら**リロード**すること。

登録直後は一覧に出ないことがあるが、**アップロードが通れば登録はできている**。

### ⑦ 掲載情報

**スクリーンショットのサイズは、欄に表示されている寸法しか受け付けない。**

| 欄 | 必要な寸法 | 撮り方 |
|---|---|---|
| iPhone 6.9インチ | 1320×2868 | iPhone 17 Pro Max シミュレータがこの解像度 |
| iPhone 6.5インチ | 1242×2688 | 上記から生成 |

**iPad / Apple Watch のタブは、ビルドを添付するまで要求されてくる。**
App Store Connect はビルドの `UIDeviceFamily` を見て初めて対応端末を判断するため。
iPhone専用アプリならビルド添付後に要求されなくなる。**iPad用を作る必要はない。**

⚠️ **説明文は plain text の単独ファイルで用意すること。**
Markdownファイルの中にコードブロックで入れておくと、**ファイル全体をコピペする事故が起きる**（実際に起きた）。

### ⑧ 提出前に必ず詰まる3か所

| 症状 | 対処 |
|---|---|
| ビルド行に「コンプライアンスがありません」 | ビルド行の **管理** → 暗号化「いいえ」 |
| 「審査用に追加」が押せない | **アプリのプライバシー**でポリシーURL入力＋「データを収集しません」を申告 |
| 配信地域 | **価格および配信状況**で日本のみに限定 |

その他: アプリ情報でカテゴリと年齢制限アンケート（賭博系すべて「なし」→ 4+）。
App Review情報の「サインインが必要です」は、ログインの無いアプリでは**チェックを外す**。

### ⑨ 初回提出は Guideline 2.1 の情報要求で一度は却下されると思っておく

新規アプリの初回提出では、コードに問題が無くても
**Guideline 2.1 - Information Needed** で差し戻されることが多い。
これは不具合の指摘ではなく「審査に必要な情報を出せ」という要求。

聞かれるのは毎回ほぼ同じ7項目。

1. 実機で撮った画面収録（起動から主要機能まで）
2. テストした端末とOSの一覧
3. アプリの機能と対象ユーザー、解決する課題
4. 主要機能への到達手順、ログイン情報やサンプルファイル
5. 使っている外部サービス・SDK
6. 地域による違いの有無
7. 規制業種や第三者の権利物を扱っていないか

**最初から App Review Information の「メモ」欄に書いておけば、この往復を避けられる。**
雀算の回答は `store/review-reply.txt` にある。次のアプリでも構成をそのまま使える。

画面収録は**実機で撮る**こと。iPhoneの コントロールセンター → 画面収録 が一番早い。

⚠️ **返信欄とメモ欄はどちらも4000文字まで。** 7項目を丁寧に書くとすぐ超える。
雀算の回答は削って3974文字に収めた。文字数は先に確認しておくこと。

```bash
wc -m store/review-reply.txt
```

### ⑩ アプリ内課金を入れる場合

**無料アプリなら銀行口座も税務情報も不要。だが課金を1つ入れると全部必要になる。**

- 有料App契約への同意
- 銀行口座の登録
- 税務情報の提出（日本＋米国向け W-8BEN）

手数料は Small Business Program に申請すれば 30% → **15%**。**必ず申請する。**
最初のApp内課金は**アプリ本体と一緒に審査**される。

課金を後回しにして先にリリースする判断もできる（雀算はその方針）。

---

## 6. 使い回せる道具

雀算のリポジトリに、Swift + CoreGraphics で画像を生成するスクリプトが2本ある。
デザインツール不要。数値を書き換えるだけで次のアプリにも使える。

### アプリアイコン — `Tools-MakeIcon.swift`

```bash
swiftc -O Tools-MakeIcon.swift -o makeicon && ./makeicon AppIcon.png
```

コツ（実際に直したもの）:
- ホーム画面では60px程度まで縮む。**細い線や模様は消える**のでシルエットで見せる
- 角丸マスクで端が欠ける。**全体を86%程度に縮めて余白を確保**
- `sips -Z 180` で縮小して判別できるか必ず確認

Assets への入れ方は `AppIcon.appiconset/Contents.json` の `platform: ios` かつ `appearances` の無い項目に `filename` を足すだけ。

### スクリーンショット — `store/MakeScreenshots.swift`

生スクショに見出しを載せて指定サイズに組む。

```bash
./makeshots <生スクショのフォルダ> <出力先>            # 6.9インチ
./makeshots <生スクショのフォルダ> <出力先> 1242 2688  # 6.5インチ
```

---

## 7. 検証コマンド集

```bash
# ロジックのテスト（Xcode不要・速い）
cd Core && swift test

# シミュレータ
xcrun simctl boot "iPhone 17 Pro Max"
xcrun simctl install booted /path/App.app
xcrun simctl launch booted com.zzzjjj080.App
xcrun simctl terminate booted com.zzzjjj080.App   # 永続化の確認に使う
xcrun simctl io booted screenshot out.png
xcrun simctl pbpaste booted                        # コピー機能の検証
xcrun simctl uninstall booted com.zzzjjj080.App    # 初回起動の再現

# 実機の確認
xcrun devicectl list devices
xcrun devicectl device info details --device <ID> | grep -i udid
```

**永続化の確認は必ず `terminate` → `launch`。** 画面遷移だけでは確認にならない。

---

## 8. 日記アプリを作るときに追加で効いてくる話

雀算と違って**個人的な文章を扱う**ので、プライバシーまわりの判断が変わる。

- **端末内保存に閉じるなら**、雀算と同じく「データを収集しません」で通る。プライバシーポリシーも流用できる
- **iCloud同期を入れるなら**、データが端末外に出る。プライバシーポリシーの書き換えが必要。SwiftDataは `.modelContainer` の設定でCloudKit連携できるが、**同期は後から足すと移行が面倒なので最初に決める**
- **写真を添付するなら** `NSPhotoLibraryUsageDescription` が必要。App Privacyの申告項目も増える
- **Face IDロックを付けるなら** `NSFaceIDUsageDescription` が必要
- 日記は**検索**と**書き心地**が価値の中心になる。雀算の「入力速度」に相当するものとして、最初にそこを詰めるとよい

SwiftDataの使い方は雀算の `SavedGame.swift` が参考になる。
一覧表示用の項目は普通のプロパティに出し、復元用の全体はCodableでData化して1カラムに入れる方式。

---

## 9. Claude Codeへの依頼で効果的だった指示

- 「ビルドが通った」で終わらせず、**シミュレータで実際にタップして確認させる**
- 変更のたびに**小さくコミット**させる（日本語で、なぜそうしたかを書かせる）
- 推測で答えさせない。**バイナリを検索する・実際に起動する・curlで確認する**など実物で確かめさせる
- 間違えたときは**その場で認めて訂正させる**（雀算では何度かあった）
- 仕様の要望が技術的に矛盾するときは、**言われた通りに作るのではなく矛盾を指摘させる**（クリアの挙動がこれで正しく落ち着いた）

---

## 10. 雀算の最終状態（参考）

- リポジトリ: https://github.com/zzzjjj080/jansan
- 公開ページ: https://zzzjjj080.github.io/jansan/
- Bundle ID: `com.zzzjjj080.Jansan` / App ID: 6802013584
- iOS 18.0以降 / iPhone / 縦向き / 日本のみ配信 / 無料
- テスト45本
- **状態: 審査提出済み**
- 未実装: カンパ（App内課金）の本番検証（銀行・税務情報の登録待ち）
