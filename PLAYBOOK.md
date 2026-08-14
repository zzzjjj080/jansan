# iPhoneアプリ開発 引き継ぎ書

雀算（麻雀スコア記録アプリ）を、HTMLプロトタイプからApp Store提出直前まで作った記録。
**次のiPhoneアプリを作るときに、このファイルの内容をClaude Codeへ最初に渡す**ことを想定してまとめている。

雀算固有の話ではなく「次も必ず使う知識」を中心に書いた。
特に **「実際に踏んだ罠」の章は必ず読ませること**。ここを知らないと同じ時間を溶かす。

---

## 0. 次のチャットでの渡し方

新しいClaude Codeのチャットで、このファイル全体を貼り付けたうえで、こう書けばよい。

> 前回iPhoneアプリを1本作ったときの引き継ぎ書です。これを踏まえて、今回は〇〇というアプリを作りたい。
> まず要件を整理してから、同じ進め方で始めてください。

---

## 1. 開発環境（このMacの状態）

| 項目 | 状態 |
|---|---|
| Mac | Apple Silicon / macOS 26 |
| Xcode | 26.6（インストール済み） |
| Swift | 6.3 |
| Apple Developer Program | 登録済み（$99/年） |
| GitHub | ユーザー名 `zzzjjj080` / SSH鍵設定済み・パスフレーズなし |
| git identity | jin / zzzjjj080@gmail.com |
| Homebrew | **入っていない** |
| gh (GitHub CLI) | **入っていない** |

**Claude Codeの権限設定は済んでいる。** `~/.claude/settings.json` で Bash・Read・Edit・Write・Glob・Grep を全許可にしてあるので、
毎回の許可プロンプトは出ない。外部送信を伴う操作だけ確認が入る。

---

## 2. うまくいった進め方（この順番を推奨）

### ① まずHTMLでプロトタイプを作る

Swiftを書く前に、**ブラウザで動くHTML1枚**で操作感を作り込んだ。これが非常に効いた。

- 仕様の迷いをSwift移植前に全部潰せる
- 実機もXcodeも不要で、修正が数秒で反映される
- 「ここはこうしたい」の議論が画面を見ながらできる

雀算では、この段階で自動確定のタイミング、キー配置、色分けなど**60項目以上の調整**を済ませていた。
Swiftに入ってからの手戻りはほぼゼロだった。

### ② ロジックだけを先にSwift Packageへ移す（UI抜き）

`JansanCore` という**UIに依存しないSwift Package**を作り、計算ロジックだけを移植してテストを書いた。

これの利点が大きかった。

- Xcodeのインストールを待たずに `swift build` / `swift test` で進められる
- 一番壊れやすい部分（点数の逆算、カーソル移動、集計）がテストで固定される
- UIを何度作り直しても、計算が壊れていないことを毎回1秒で確認できる
- 最終的にテスト39本になり、リファクタが怖くなくなった

**型でバグを防ぐ設計にした**のも効果的だった。HTMLでは4つのフラグで表していたマスの状態を、Swiftではenumにした。

```swift
enum Entry {
    case empty          // 入力待ち
    case resting        // その局は不参加
    case entered(Int)   // 手入力
    case derived(Int)   // 合計0から逆算
}
```

「手入力なのにお休み」のような**あり得ない組み合わせをそもそも作れなくなる**。

### ③ UIを載せる

`@Observable`（iOS 17+）で状態クラスを1つ作り、Viewはそれを見るだけにした。
`ObservableObject` + `@Published` は不要。

### ④ シミュレータで実際に触って確認する

Claude Codeからシミュレータを操作できる。**「ビルドが通った」で終わらせず、必ず実際にタップして確認させること。**
これで実際にいくつもバグが見つかった。

---

## 3. Xcodeプロジェクト作成時にやること

新規プロジェクトを作った直後に、**必ず**以下を確認・変更する。デフォルトのままだと事故る。

### 作成ダイアログで

| 項目 | 設定 |
|---|---|
| Organization Identifier | `com.zzzjjj080`（変更不可なので慎重に） |
| Testing System | **Swift Testing**（Noneにしない） |
| Storage | **None**（SwiftDataは自分で設計してから入れる） |
| Create Git repository | **チェックを外す**（リポジトリはルート側で作る） |

### 作成直後にビルド設定を修正（ここが最重要）

```
IPHONEOS_DEPLOYMENT_TARGET = 26.5  →  18.0
```

**Xcodeは最新OSを初期値にする。** 26.5のままだと最新OSの端末にしか入らず、ほぼ誰にも届かない。
これは気づかないと致命的。iOS 18なら主要な機能（SwiftData / @Observable / Swift Charts / ContentUnavailableView / Color.mix）が全部使える。

```
TARGETED_DEVICE_FAMILY = "1,2,7"  →  1
```

初期値はiPhone+iPad+Vision Pro。iPad対応するとレイアウトの作り込みとiPad用スクリーンショットが要る。
**最初はiPhoneのみに絞る**のが吉。

```
developmentRegion = en  →  ja
knownRegions に ja を追加
```

日本語アプリなら必須。これをやらないと、**スワイプ削除が「Delete」、編集ボタンが「Edit」**のまま英語で出る。
`ja` にするだけでシステム由来のUIが全部日本語になる。

```
INFOPLIST_KEY_CFBundleDisplayName = "アプリ名"
```

ホーム画面の表示名。設定しないと英語のターゲット名が出る。

```
INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait
```

初期値は横向きも含む。縦専用レイアウトなら固定しておく。

---

## 4. 実際に踏んだ罠（最重要）

### 4-1. Command Line Tools だけでは `swift test` が動かない

XCTestもSwift TestingもXcode.appに同梱されている。CLTだけの状態だとテストが走らない。
Xcodeのインストール待ちの間にテストを書くなら、**素のexecutableターゲットで自前のアサーションを回す**という手がある（実際そうした）。

### 4-2. `xcode-select -p` は当てにならない

Xcodeを入れても、**明示的に選択していない状態**がある。`xcode-select -p` はフォールバックで正しいパスを返すのでビルドは通るが、
シミュレータ連携などは「選択されていない」と判断して動かない。

本当の確認はこれ。

```bash
ls -l /var/db/xcode_select_link   # これが無ければ未選択
```

未選択なら以下を**ユーザー自身がターミナルで**実行する（sudoなのでClaudeからは実行できない）。

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

### 4-3. シミュレータを複数起動していると入力が別の端末に飛ぶ

2台booted状態だと、タップが意図しない方に送られる。**使わない方は落とす。**

```bash
xcrun simctl shutdown "iPhone 17"
xcrun simctl list devices booted   # 1台だけになっているか確認
```

### 4-4. `.storekit` をプロジェクト管理下に置くとアプリに同梱される

アプリ内課金のローカルテスト用ファイルを `Jansan/Jansan/` に置いたら、
**リリースビルドのapp内に `.storekit` が入ってしまった。** テスト用設定をApp Storeに出荷することになる。

必ず検証すること。

```bash
find path/to/Release-iphonesimulator/App.app -name "*.storekit"
```

`.xcscheme` に手書きでパスを書くのは相対パスの基準が分かりにくく、3回試して当たらなかった。
**Xcodeの Edit Scheme → Run → Options → StoreKit Configuration から設定させる**のが確実。

### 4-5. `#if DEBUG` が効いていることは実物で確認する

開発用のデモデータ投入ボタンなどは `#if DEBUG` で囲むが、**本当に消えているかはバイナリを見る**。

```bash
xcodebuild -configuration Release ... build
strings path/to/App.app/App | grep "デモデータ"   # 何も出なければOK
```

### 4-6. アプリ内課金を入れると銀行口座と税務情報が必須になる

無料アプリのままなら App Store Connect に銀行情報は不要。
だが**カンパ（投げ銭）を1つ入れるだけで**以下が全部必要になる。

- 有料App契約への同意
- 銀行口座の登録
- 税務情報の提出（日本の分 + 米国向け W-8BEN）

手数料は Small Business Program に申請すれば 30% → **15%**。**必ず申請する。**

### 4-7. 機能を足したら既存の説明文の整合性を確認する

雀算では「インターネットに接続しません」とプライバシーポリシー・サポートページ・ストア掲載文・READMEの
**4か所**に書いていた。あとからStoreKit（課金）を入れたことで、**この記述が全部嘘になった**。

虚偽のプライバシー表示は審査で問題になる典型。機能追加のたびに文言を見直すこと。

### 4-8. 個人でDeveloper Programに登録すると本名がApp Storeに公開される

販売者名として本名が出る。屋号やハンドルネームにはできない。
避けたいなら法人登録しかなく、D-U-N-S番号の取得から必要になる。**登録前に納得しておくこと。**

### 4-9. Xcodeで実行先が「My Mac」になっていると意味不明なエラーが出る

`Unable to resolve module dependency: 'UIKit'` が出たら、まず実行先を疑う。
iPhoneアプリをMac向けにビルドしようとしているだけ。

---

## 5. 検証のやり方（コマンド集）

### ビルドとテスト

```bash
# ロジックのテスト（Xcode不要、速い）
cd Core && swift test

# アプリのビルド
cd App && xcodebuild -project App.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -derivedDataPath /tmp/dd build 2>&1 | grep -E "error:|BUILD"
```

### シミュレータ操作

```bash
xcrun simctl boot "iPhone 17 Pro Max"
xcrun simctl install booted /tmp/dd/Build/Products/Debug-iphonesimulator/App.app
xcrun simctl launch booted com.zzzjjj080.App
xcrun simctl terminate booted com.zzzjjj080.App     # 永続化の確認に使う
xcrun simctl io booted screenshot out.png
xcrun simctl pbpaste booted                          # コピー機能の検証
xcrun simctl uninstall booted com.zzzjjj080.App      # まっさらな初回起動の再現
```

### 永続化の確認

「アプリを閉じても続きから」を検証するときは、**必ず `terminate` してから `launch` し直す**。
画面遷移だけでは確認にならない。

---

## 6. 使い回せる道具

雀算のリポジトリに、**Swift + CoreGraphics で画像を生成するスクリプト**を2本置いてある。
次のアプリでも数値を書き換えるだけで使える。

### アプリアイコン生成 — `Tools-MakeIcon.swift`

1024×1024のPNGを吐く。デザインツール不要。

```bash
swiftc -O Tools-MakeIcon.swift -o makeicon && ./makeicon AppIcon.png
```

**アイコンを作るときのコツ**（実際に直したもの）

- ホーム画面では60px程度まで縮む。**細い線や模様は消える**ので、シルエットで見せる
- 角丸マスクで端が欠ける。**全体を86%程度に縮めて余白を確保**する
- 必ず `sips -Z 180` で縮小して、小さくても判別できるか確認する

Assets への入れ方は、`AppIcon.appiconset/Contents.json` の
`platform: ios` かつ `appearances` が無い項目に `filename` を足すだけ。ダークとティントは未指定なら通常版が使われる。

### App Store用スクリーンショット生成 — `store/MakeScreenshots.swift`

生のスクリーンショットに見出しを載せて、6.9インチ（1320×2868）に組む。

- **6.9インチ1種類だけ登録すれば、他サイズはApple側で自動縮小される**
- iPhone 17 Pro Max のシミュレータが 1320×2868 ちょうど

---

## 7. リリース準備チェックリスト

### 先に着手（時間がかかる）

- [ ] **Apple Developer Program 登録**（$99/年、承認に24〜48時間）
- [ ] **Small Business Program 申請**（手数料15%になる）
- [ ] iPhoneの「Apple Developer」アプリから登録するのが早い。写真付き身分証が要る
- [ ] 氏名は身分証と一字一句合わせる。住所はローマ字でも通った

### 公開ページ（App Storeが両方必須）

- [ ] プライバシーポリシー
- [ ] サポートページ

GitHub Pages が無料で使える。**リポジトリを Public にして、`/docs` フォルダを公開対象に指定する。**
Settings → Pages → Source: Deploy from a branch → Branch: main → フォルダ: `/docs`。
反映に1〜3分かかる。

雀算のものが `docs/` にあるので、文面はそれを流用すればよい。

### 提出物

- [ ] アプリアイコン（1024×1024）
- [ ] スクリーンショット（6.9インチ、3〜5枚）
- [ ] App名（30字）/ サブタイトル（30字）
- [ ] キーワード（100字、カンマ区切り、スペース禁止）
  - **App名とサブタイトルの語は繰り返さない。** Appleが別途索引するので枠の無駄
- [ ] 説明文
- [ ] プロモーションテキスト（170字、審査なしで差し替え可能）

### 提出時に聞かれること

| 質問 | 通信しないアプリの場合 |
|---|---|
| 輸出コンプライアンス（暗号化） | いいえ |
| 広告識別子（IDFA） | いいえ |
| データ収集 | 収集しません |
| 年齢制限 | 4+（賭博機能が無ければ麻雀でも4+） |

---

## 8. 設計上の判断で良かったこと

- **ロジックをUIから完全に分離した** — テストが書け、UIを何度でも作り直せた
- **状態をenumで表した** — あり得ない状態が作れない
- **保存を2種類に分けた** — 「入力途中の自動保存（1件）」と「明示的に残す記録（複数）」は別物として設計した。ユーザーの理解も楽
- **表示用の値を保存データに含めた** — 小数点モードの状態を記録側に持たせた。持たせないと、あとでモードを変えたときに過去の記録が10倍に見える
- **プロトタイプの独自実装をOS標準に置き換えた** — 手描きSVGのグラフ → Swift Charts、`mailto:` → `ShareLink`、Web版で動かなかったバイブ → `UIImpactFeedbackGenerator`

---

## 9. Claude Codeへの依頼で効果的だった指示

- 「ビルドが通った」で終わらせず、**シミュレータで実際にタップして確認させる**
- 変更のたびに**小さくコミット**させる（日本語のコミットメッセージで、なぜそうしたかを書かせる）
- 推測で答えさせない。**バイナリを検索する、実際に起動する、curlで確認する**など実物で確かめさせる
- 自分が間違えたときは**その場で認めて訂正させる**（雀算では私が数回間違えた）

---

## 10. 雀算の現状（引き継ぎ時点）

- リポジトリ: https://github.com/zzzjjj080/jansan
- 公開ページ: https://zzzjjj080.github.io/jansan/
- Bundle ID: `com.zzzjjj080.Jansan`
- 対応: iOS 18.0以降 / iPhone / 縦向き
- テスト: 39本
- **残作業**: Developer Program承認 → App Store Connect登録 → アーカイブ提出
- **未検証**: アプリ内課金の購入フロー（Sandboxでの確認が必要）
