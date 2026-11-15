<div align="center">
  <img src="VoiceInk/Assets.xcassets/AppIcon.appiconset/256-mac.png" width="180" height="180" alt="VoiceInkのアプリアイコン" />
  <h1>VoiceInk</h1>
  <p>話した内容をすばやく文字にする、macOS向け音声入力アプリ</p>

  [![ライセンス](https://img.shields.io/badge/ライセンス-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
  ![対応環境](https://img.shields.io/badge/対応環境-macOS%2015.0%2B-brightgreen)
  [![本家の最新リリース](https://img.shields.io/github/v/release/Beingpax/VoiceInk)](https://github.com/Beingpax/VoiceInk/releases)
  ![本家の累計ダウンロード数](https://img.shields.io/github/downloads/Beingpax/VoiceInk/total)
  ![本家のスター数](https://img.shields.io/github/stars/Beingpax/VoiceInk?style=social)
  <p>
    <a href="https://tryvoiceink.com">本家の公式サイト</a> •
    <a href="https://www.youtube.com/@tryvoiceink">本家のYouTubeチャンネル</a>
  </p>

  <a href="https://tryvoiceink.com">
    <img src="https://img.shields.io/badge/本家の配布版-ダウンロード-blue?style=for-the-badge&logo=apple" alt="本家のVoiceInkをダウンロード" width="250"/>
  </a>
</div>

---

VoiceInkは、話した内容をすばやく文字にするmacOS向けのアプリ。
本家の情報と配布版は[公式サイト](https://tryvoiceink.com)で確認できる。
このリポジトリは独自機能を追加したフォークであり、本家の公式配布版とは異なる。
独自機能と利用条件は、後述の「フォーク独自の変更一覧」以降を参照。

![Mac版VoiceInkの画面](https://github.com/user-attachments/assets/12367379-83e7-48a6-b52c-4488a6a04bba)

本家の作者は、約5か月間の開発を経てソースコードを公開した。
効率とプライバシーを重視し、快適に使える音声入力アプリを目指している。
本家のライセンス購入は継続的な開発を支え、自動更新や優先サポートなどの提供につながる。
これらは本家の配布版についての案内であり、このフォークでの提供を約束するものではない。

## 主な機能

- 🎙️ **音声認識**: ローカルのAIモデルなどで、話した内容をすばやく文字にする。
- 🔒 **プライバシーに配慮した処理**: ローカル処理を選べば、音声を端末外へ送らずに認識できる。クラウド機能や同期は別途通信する。
- ⚡ **アプリやURLに応じたモード切替**: 入力先に合わせて、事前に設定したモードを適用する。
- 🧠 **文脈を利用した補正**: 画面などから取得した文脈をAI補正に利用する。
- 🎯 **共通ショートカット**: キーボードやマウスの操作を設定し、録音や押している間だけ録音する操作を呼び出す。
- 📝 **個人用辞書**: 独自の語彙や専門用語、文字列の置換を登録する。
- 🔄 **用途別のモード**: 文体や入力する場面に合わせて、AI補正の設定を切り替える。
- 🤖 **AIアシスタント**: 音声から対話形式でAIを利用する。

## はじめに

### 本家の配布版を入手する

[本家の公式サイト](https://tryvoiceink.com)では、無料試用ができる配布版を案内している。
購入は本家の継続的な開発と、新機能・更新の提供を支える。

#### Homebrewで入手する

本家の配布版は、次のコマンドでもインストールできる。
このコマンドでは、当フォーク独自の変更は導入されない。

```shell
brew install --cask voiceink
```

### ソースコードからビルドする

[ビルド手順](BUILDING.md)に従って、自分でビルドできる。
本家の購入版には、自動更新やDiscord・メールによる優先サポートなどが付く。
当フォークをビルドする場合は、後述の「このフォークを使う場合のビルドと起動」も参照。

## フォーク独自の変更一覧

このリポジトリは上流の VoiceInk を元にしたフォーク。
カスタマイズの統合先はこのフォークの `main`。上のダウンロード先・Homebrew・リリースバッジは
フォーク元の配布版を指し、以下の変更を含むビルドの入手先ではない。

以下はフォーク元との共通祖先以降に追加した変更の一覧。コミット番号は実装を確認するための参照。

| 変更 | 動作・利用条件 | 実装コミット |
| --- | --- | --- |
| 日本語のフィラー除去 | 「えーと」「あのー」などを既定候補に追加し、空白のない日本語でも除去できるようにした。保存済みの独自リストは維持する。 | `7b34b4bb` |
| ローカル音声検出 | Silero VAD で発話を検出する。リアルタイム送信では発話前後の余白を残し、無音だけの送信を抑制する。 | `ac5db988` |
| 通信障害時の復旧 | クラウド文字起こしが失敗した場合、導入済みの Whisper モデルで Mac 内で再処理する。設定で無効化・モデル指定が可能。モデル未導入時は元のエラーを表示し、自動ダウンロードや別クラウドへの転送はしない。 | `466a2a85` |
| 辞書の自動バックアップ | 既定で起動時と5分ごとに変更を確認し、JSONを保存して最新30世代を保持する。既定の保存先はアプリのデータフォルダ内の `DictionaryBackups`。設定で保存先を変更でき、復元は辞書設定の「読み込む」から行う。 | `187e3d1b` |
| Web入力欄での自動学習 | Web入力欄の取得・貼り付け範囲の復元、送信後に空になる欄、WebKitの隠れた欄、日本語の差分抽出、製品名・短いAIモデル名の審査を改善した。詳細は次節。 | `1ed58056`, `5e51e1b0`, `0736c200`, `195fa9e8`, `c3178d64` |
| 手動の修正登録 | 自動取得できない入力欄で手動登録を案内する。辞書設定から置換登録を開けるほか、履歴の元テキストを使って修正を登録できる。 | `98e2dd35`, `12984c9e` |
| 自動学習の統計 | アプリ別の取得・候補生成などの状況と、AI審査の利用量を記録する。入力欄ごとの学習状況を確認するために使う。 | `12984c9e` |
| 利用量と推定料金 | 文字起こしの処理先別に回数・録音時間・失敗・中止を月別（UTC）で記録する。AI補正と自動学習の審査も別に集計し、組み込み単価と文字数などから推定料金を表示する。実請求やサービス側の残枠とは一致しない。料金表示の文字色も調整した。 | `466a2a85`, `12984c9e`, `fc1dfdce` |
| iCloud辞書同期 | 設定したiCloudコンテナを使ってMacとiOSの辞書を同期する。CloudKitの取り込み完了後に重複エントリを整理する。対応する署名・権限・iCloudアカウントが必要。 | `5c8b1302`, `6e03f810` |
| フォークのデータ分離 | バンドルID・データ保存先・キーチェーンを配布版から分離し、フォーク元の自動更新を無効化した。詳細は後述のローカルビルドの制約を参照。 | `8a4f2b31`, `5c8b1302` |
| ビルド・個人配布 | ローカルビルドと起動手順、DMG作成を追加した。GitHubリリース公開用の構成を経て、現在はDeveloper ID署名・Apple公証を行う個人配布用DMGを作る。公証は状態をポーリングして待つ。 | `9e3d6aef`, `b1a0903f`, `6ec2663b`, `3a1b3941` |
| README整備 | データ保存先・iCloud・起動手順・Auto Learnの変更と利用条件を記載した。 | `805b6277`, `b3008b95` |

音声認識の実行先、AI補正、自動学習の審査、iCloud同期はそれぞれ独立した設定・通信経路になる。
完全オフラインで動くのはローカル処理を選んだ場合であり、クラウド機能を使う場合には当てはまらない。

## フォーク正式版2.26

このフォークの `main` は本家2.26（`4bc74cad`）と独自機能を統合した正式版。
本家の配布版とは別のアプリであり、インストール済みアプリは自動更新しない。
本家のAuto Learn、Smart Punctuation、入力・録音・ストリーミングの改善を取り込み、
日本語フィラー除去、WebKit入力欄の取得、利用量集計、辞書バックアップ、
iCloud同期、ローカルビルドのデータ分離を維持する。

### Auto Learnの変更と利用条件

本家の新方式に合わせ、学習は主に置換候補の提示として扱う。
新規設定では外部AIを使わないルール審査を利用でき、必要な訂正回数を1〜3回で選べる。
AI審査を設定した場合は自動／手動を選択できる。手動審査では「今すぐ確認」（英語表示では「Review Now」）で審査し、
承認された候補を登録する。自動審査の場合は候補パネルで登録を承認する。
候補パネルは10秒で自動的に却下するため、従来の自動登録とは動作が異なる。
既存のAIプロバイダー・モデルと手動送信の設定は移行する。
旧方式の「置換と語彙を同時登録する」審査指示は使わない。

- 日本語の製品名やAIモデル名の音声認識誤りは、同じ語の表記を復元する場合に置換候補とする。
  一般的な役割名や、長い名前の一部だけの危険な置換は審査対象から除外する。
- 送信後に空になるWeb入力欄は、最後に読めた空でない内容から訂正を検出する。
  値の変更通知、定期的な読み直し、貼り付け直後の短時間の再試行を維持する。
- WebKitでは選択位置から編集可能な親要素を探す。日本語の差分は文字種の境界で分割する。
- 取得失敗時の手動登録案内、辞書画面からの手動登録、取得統計、AI審査の利用量集計を維持する。
- AI審査には専用の45秒以上のタイムアウトを使う。

入力欄の読み取りにはmacOSのアクセシビリティ許可が必要。
入力欄によって取得できない場合があり、すべての訂正が登録される保証はない。
クラウドのAI審査を選ぶと修正候補のテキストがそのプロバイダーへ送信される。
本家のSmart Punctuationは入力位置に合わせた空白・大文字・句読点の調整であり、
次節のHorizonによる日本語の句読点補完とは別の処理。

オフラインの確認:

```shell
bash Tests/run-auto-learn-correction-diff-tests.sh
bash Tests/run-auto-learn-web-focus-tests.sh
bash Tests/run-output-filter-tests.sh
bash Tests/run-reliability-tests.sh
bash Tests/run-recording-speech-gate-tests.sh
```

これらは本番の外部AIや実際のアプリ入力欄での審査・登録、iCloudの端末間同期を
検証するものではない。正式版も従来のフォークと同じデータ保存先を使うため、
起動して試す前に辞書を書き出して保管する。新しいAuto Learnは候補ファイルを移行するので、
旧版へ戻しても新しい候補が旧版で読めるとは限らない。

## HaaS-ja / Horizon の同梱実行環境

Apple Silicon版では、音声認識用のspeech.cppライブラリ、ポータブルPython、
Horizonの句読点補完処理をアプリに同梱する。Homebrew、Pythonの別途インストール、
常駐サーバーの起動は不要。モデルの重みは同梱せず、初回に約655MBをダウンロードする。

新規起動時は **HaaS-ja + Horizon** を初期選択する。初回設定画面でモデルを取得し、
固定バージョンのファイルサイズとSHA-256を確認してから利用可能にする。
言語は自動判定、リアルタイム認識はオフ。取得後はオフラインで利用できる。
「モデル」のカスタムプロバイダー画面でも取得・中止・再試行ができる。
モデルはアプリ専用のApplication Support内に保存し、バックアップ対象から除外する。

処理経路は VoiceInk → 同梱Python → 同梱speech.cppのC API → HaaS-ja → Horizon。
録音ごとに専用プロセスを起動し、処理後に終了する。認識の中止・タイムアウト・アプリ終了時も
そのプロセスを停止する。ローカルHTTPサーバーや固定ポートは使用しない。
既存の外部サービス用カスタムモデルは、保存済みの接続先を引き続き使う。
AI補正やAuto Learnにクラウドを選んだ場合は、その処理のテキストが外部送信される。

ビルド前に `python3 scripts/prepare-local-haas-runtime.py` で実行環境を準備する。
`make build` / `make local` と配布ビルドは自動で準備する。
配布用のネイティブ実行ファイルは、アプリと同じ署名IDで署名してから同梱する。
直接Xcodeからビルドする場合も、先に準備コマンドを実行する。
現時点の実行環境はarm64専用。実行部分のバージョン・取得元・ハッシュと依存パッケージは
`scripts/prepare-local-haas-runtime.py` と `runtime/local-haas/requirements.txt` に固定する。
エンドユーザー環境では実行コードのダウンロードやpipの実行を行わない。

検証コマンド:

- `bash Tests/run-local-haas-defaults-tests.sh`: 初期設定と既存設定の保持
- `bash Tests/run-local-haas-runtime-tests.sh`: モデル検証・破損・中止・タイムアウト
- `bash Tests/run-local-haas-runtime-tests.sh --live`: 初回モデル取得、合成日本語音声の認識、
  通信を拒否した新しい実行環境での再認識（モデルは一時フォルダに保存）


## 個人配布用の DMG

このフォークのビルドは GitHub では配布しない。Developer ID で署名し、Apple の公証を通した
DMG を個人的に配る。

必要なもの:

- Developer ID Application 証明書
  （Xcode → Settings → Accounts → チームを選ぶ → Manage Certificates → 「+」）
- 公証用のキーチェーンプロファイル、またはApp Store Connect APIキー
- 既定の配布対象はApple Silicon・macOS 15以降。Intel版はこの配布手順では検証していない。

公証の資格情報はリポジトリに保存せず、環境変数で指定する。

```shell
export VOICEINK_NOTARY_PROFILE="your-notarytool-profile"
make personal-dmg
```

APIキーを直接使う場合は `VOICEINK_NOTARY_KEY`（p8のパス）、
`VOICEINK_NOTARY_KEY_ID`、`VOICEINK_NOTARY_ISSUER` を指定する。
署名チームは `LocalBuild.xcconfig` から読み、`VOICEINK_TEAM_ID` で上書きできる。

`scripts/build-personal-dmg.sh` が、アーカイブ作成 → Developer IDで署名して書き出し → DMG作成 → 公証申請 →
公証チケットの添付まで行う。公証時はDMGをAppleへ送信するが、GitHub Releasesなどへの公開はしない。
DMGにはライセンス原文、第三者ソフトウェアの告知、アプリと依存物の対応ソースを同梱する。出力は `~/Downloads/VoiceInk-dmg/VoiceInk.dmg`。証明書がない場合は作成手順を
表示して止まる。公証を飛ばして署名と DMG だけ作る場合は `--skip-notarization`。

## このフォークを使う場合のビルドと起動

このフォークは配布版と同じ
`make local` でビルドするが、**起動手順に 1 点だけ違いがある**: 成果物は `~/Downloads/VoiceInk.app`
に作られるので、ランチャー（Raycast など）やアクセシビリティ許可の管理で通常のアプリとして扱えるようにするため
`/Applications` に置くこと。

### ビルドから起動まで

前提: 対応するXcodeとHomebrewが導入済みであること。
`make local` は Apple Development による自動署名が必須で、ad-hoc署名へのフォールバックはない。
署名チームは `LocalBuild.xcconfig` の `DEVELOPMENT_TEAM` で設定する。
別の開発者がビルドする場合は、自分のチーム・バンドルID・iCloudコンテナと権限に合わせて
`LocalBuild.xcconfig` と `VoiceInk/VoiceInk.local.entitlements` を調整する。初回は Metal
ツールチェーンが必要になる場合がある（`xcodebuild -downloadComponent MetalToolchain`）。

```shell
# 1. ビルドに必要なツールの確認
make check

# 2. ローカルビルド（必要なWhisperの依存物を用意してからビルドする）
# 所要時間は環境によって異なる。アプリの前回のビルド出力は作り直す。
make local

# 出力先を変える場合: make local APP_OUTPUT_DIR=/path/to/output
# 署名証明書を指定する場合: make local LOCAL_CODESIGN_IDENTITY="Apple Development: ..."

# 3. 起動中の VoiceInk を終了してから、確実に新しい方を使わせる
osascript -e 'tell application "VoiceInk" to quit'
rm -rf /Applications/VoiceInk.app
ditto ~/Downloads/VoiceInk.app /Applications/VoiceInk.app
xattr -cr /Applications/VoiceInk.app   # 隔離属性の除去
open -a /Applications/VoiceInk.app
```

既存アプリをDMGにまとめるだけなら `make package-dmg` を使える（アプリの再ビルド・署名は行わない）。
その場合も、先に `scripts/prepare-distribution.py` で告知文書と対応ソースを用意する。
必要な依存物が見つからない、固定リビジョンと一致しない、ライセンス原文がない場合は配布処理を止める。

配布準備処理は、ビルド時のSwiftパッケージ、Whisper、transcribe.cpp、NeMo文字処理の
ソースとサブモジュールを収集する。Rust依存はCargo.lockに従って収録するため、
Python 3.12以降の `python3`、`git`、`cargo` と初回の取得用ネットワーク接続が必要。
バイナリ依存物のリビジョンは `scripts/distribution-dependencies.json` で固定する。
標準以外の場所でWhisperをビルドした場合は `VOICEINK_WHISPER_SOURCE` を指定する。

### よく出る確認ダイアログ

- **キーチェーンの確認**（「VoiceInkがキーチェーン内の "`com.prakashjoshipax.VoiceInk.Local`"
  の…を使用しようとしています」）: ローカルビルドが API キーやライセンスキーを保存・読み出す
  ときに macOS が確認しているだけ。**「常に許可」か「許可」で問題ない**。ad-hoc 署名や別の
  署名に変えるたびに再確認を求められるが、安定した Apple Development 証明書（`make local`
  が指定する）を使い続けることで、再確認を抑えられる。
- **アクセシビリティ／マイクの許可**: 署名を変えてインストールし直すたびにやり直しが必要。
  安定した証明書を 1 つ使い続ければ再設定は不要。

### ローカルビルドの制約

- ライセンス判定は常に「購入済み」になる（`#if LOCAL_BUILD` のブロックによる）。
- 自動更新は無効。更新は新しいリリースを入れ直すか、`git pull` して再ビルドする。
- 辞書は設定したiCloudコンテナでMacとiOSの間で同期する。
- フォーク専用のバンドルIDとApplication Support内のデータフォルダを使い、配布版と共存する。
  実際の識別子・保存先はビルド設定と `AppPaths` を参照。データを消すと履歴・辞書・設定が失われる。
- 初回起動時に旧バンドルID `com.prakashjoshipax.VoiceInk` の設定を、現在の設定にないキーだけ
  コピーする。履歴DB・辞書DB・モデルファイルをコピーする処理ではない。
- データ分離には Whisper / TranscribeCpp / Refine のモデル保存先も含む。RefineのXPCサービスも
  ローカルビルドでは専用バンドルIDを使う。デバッグビルドでは辞書のCloudKit同期を無効にする。
- API キーの保存先もローカルビルド専用のキーチェーン名前空間になる。配布版で入れた
  キーは引き継がれない。


## 動作環境

- macOS 15.0以降
- 当フォークの配布用DMGはApple Silicon向け。Intel版は未検証。

## 関連資料

- [ビルド手順](BUILDING.md): ビルド方法の詳細
- [貢献方法](CONTRIBUTING.md): 本家への貢献に関する案内
- [行動規範](CODE_OF_CONDUCT.md): コミュニティの行動指針

## 開発への参加

本家は現在、プルリクエストを受け付けない方針を案内している。
個人利用のためにフォークして変更することはできる。
本家の方針は[貢献方法](CONTRIBUTING.md)を参照。

次の方法でも本家の開発に協力できる。

- [本家の課題一覧](https://github.com/Beingpax/VoiceInk/issues)で不具合を報告する
- 新機能や改善を提案する
- 資料の改善点を報告する

当フォーク固有の不具合は、[当フォークの課題一覧](https://github.com/RyoyaYahagi/VoiceInk/issues)で扱う。
本家に報告する場合は、フォーク独自の変更による問題でないことを確認する。

## ライセンスと再配布

VoiceInk本体は[GNU GPLv3](LICENSE)で公開されている。
独自変更を加えた版を配布する場合も、ライセンスと著作権表示を保持し、
配布する実行ファイルに対応するソースコードと、必要なビルド手順を入手できるようにする。
GPL本文とソースのリンクを置くだけで、すべての依存物の配布条件を満たすとは限らない。
詳細は[GNU公式のFAQ](https://www.gnu.org/licenses/gpl-faq.en.html#SourceAndBinaryOnDifferentSites)を参照。

### モデルと外部プログラム

- [HaaS-jaのGGUF版](https://huggingface.co/sakasegawa/Haas-ja-v1.0-GGUF)と
  [Horizon](https://huggingface.co/Horizon-Labs/punctuation-restoration-small)は、公開元でApache-2.0と表記されている。
- モデルや外部プログラムを同梱・再配布する場合は、それぞれのライセンス本文、著作権表示、
  同梱されている告知文書などを確認して保持する。Horizonには、基盤モデル由来の告知文書もある。
- このMac版にはHaaS/Horizonの実行環境を同梱し、モデルの重みは初回に取得する。
  ただし、音声の有無を判定するSilero VAD v5.1.2のモデルは以前から同梱しており、
  MITライセンスの原文と著作権表示を配布物に保持する。
  ダウンロードや別途導入でも、利用する各配布物の条件に従う。
- 選択できるほかのモデルが、すべてApache-2.0とは限らない。各モデルの条件を個別に確認する。
  GeminiなどのクラウドAPIには、各サービスの利用規約が別途適用される。

Apache-2.0の再配布条件は[Apache公式のライセンス本文](https://www.apache.org/licenses/LICENSE-2.0.html)を参照。

### 配布物の確認状況

配布処理は次をDMG内にまとめる。

- GPLv3本文と、依存物ごとのライセンス・著作権表示・告知文書の原文
- アプリ、Swift依存物、Whisper、transcribe.cpp、NeMo文字処理、speech.cppの固定ソース
- Swiftのサブモジュールと、ロック済みのRust依存ソース
- リビジョンと同梱モデルのハッシュを記録した一覧、再ビルドの案内、各ファイルのチェックサム

HaaS/Horizonの重みは含めず、実行環境とHorizonの告知原文を保持する。
同梱Python・依存パッケージの告知文書は実行環境内にも保持し、Silero VADのライセンスを別途収録する。
Appleの公証はライセンス条件を満たしたことを保証するものではない。
将来の依存物・モデルの追加や差し替え時には、その版の条件と告知文書を再確認する。

対応ソースにはビルドに必要な実装と手順を収録するが、Sparkleの `Tests/Resources` にある
既成のテスト用アプリ・DMG・インストーラーは含めない。これらはVoiceInkやライブラリのビルドに
使わず、Appleの公証では古い署名の実行ファイルとして拒否されるため。
除外範囲と、必要な場合に元のテスト用配布物を取得できる出所・リビジョンは一覧に記録する。

このフォークを本家の公式配布版と誤認させる案内はしない。
ライセンスが公開されていることと、名称・ロゴなどの使用条件は分けて確認する。

## 問い合わせ・不具合報告

問題が起きた場合は、次の順で確認する。

1. 利用しているリポジトリの既存の課題を確認する。
2. 同じ問題がなければ、新しい課題を作成する。
3. macOSのバージョン、アプリの版、利用モデル、再現手順などを記載する。
   APIキー、録音内容、個人情報を含むログは公開しない。

## 謝辞

### 主な技術

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp): OpenAIのWhisperモデルを高速に実行するための実装
- [FluidAudio](https://github.com/FluidInference/FluidAudio): Parakeetモデルなどの実行に利用
- [TranscribeCpp for Swift](https://github.com/Beingpax/Transcribe-cpp-swift): ローカルのGGUF音声認識モデルを扱う[transcribe.cpp](https://github.com/handy-computer/transcribe.cpp)のSwift向け配布
- [SenseVoice Small](https://huggingface.co/FunAudioLLM/SenseVoiceSmall): FunAudioLLM／Alibabaによる多言語モデル。[FunASRのモデルライセンス](https://github.com/modelscope/FunASR/blob/main/MODEL_LICENSE)が適用される

### 主な依存ライブラリ

- [Sparkle](https://github.com/sparkle-project/Sparkle): 本家の配布版で使う自動更新の仕組み。当フォークのローカルビルドでは無効
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts): ショートカット設定の仕組み
- [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin): ログイン時の自動起動
- [MediaRemoteAdapter](https://github.com/ejbills/mediaremote-adapter): 録音中のメディア再生の制御
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation): ファイルの圧縮・展開
- [Swift Atomics](https://github.com/apple/swift-atomics): 並行処理で使うアトミック操作

---

Paxによる開発に感謝します。
