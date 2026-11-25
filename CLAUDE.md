# Difframe（旧名 ひとコマ / Hitokoma）

毎日同じ時刻に全員へ同じお題が届き、その場で1枚撮って見比べる iOS アプリ。SwiftUI ＋ Firebase。
詳しい経緯・決まったこと・まだやることは、開発メモにある。作業の前に読み、大事なことが決まったり直ったりしたら更新する（日本語、やさしい言葉で）：
`~/Desktop/ice hacks/Difframe_開発メモ.md`

## 構成
- `Hitokoma/` アプリ本体、`HitokomaWidget/` ウィジェット、`Shared/` 両方で使うコード
- `firebase/` Cloud Functions と Hosting、`firestore.rules` セキュリティルール
- `Hitokoma.xcodeproj` は `make_hitokoma_xcodeproj.py` で作る（設定は `hitokoma.config.json`）
- バンドルID `com.diffframe.app`、App Group `group.com.diffframe.app`、Firebase プロジェクト `difframe-acae0`

## ビルド
```
xcodebuild -project Hitokoma.xcodeproj -scheme Hitokoma -destination 'generic/platform=iOS' -derivedDataPath "$TMPDIR/difframe_dev" -allowProvisioningUpdates build
xcrun devicectl device install app --device <UDID> "$TMPDIR/difframe_dev/Build/Products/Debug-iphoneos/Hitokoma.app"
```
- パッケージが読めないとき：`rm -rf "$TMPDIR/difframe_dev/SourcePackages"` してから `-resolvePackageDependencies`
- 実機の起動エラー 10002 は、iPhone のロック中

## 決まりごと
- 画面の文字は `L()` / `LF()` で書き、6言語（`LocalizedEN/ZH/KO/ES/FR.swift`）に訳を足す。既定は英語。訳の中の `"` は `\"` にする
- Firebase は `AppDelegate` の起動完了で設定する（App の `init` では早すぎて、電話認証が壊れる）
- 秘密のファイルは Git に入れない：`GoogleService-Info.plist`、`.p8`、`firebase/functions/.env`
- GitHub（https://github.com/sats071417-cyber/difframe）への push は、頼まれたときだけ
- ユーザーへの説明は日本語で
