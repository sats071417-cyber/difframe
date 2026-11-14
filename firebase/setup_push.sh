#!/bin/bash
# Difframe のプッシュ通知を、サーバー（Cloud Functions）に入れる。
# 使い方:  ./setup_push.sh <キーID（10文字）> <AuthKey_XXXX.p8 のパス>
set -e
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "$(dirname "$0")"
KEY_ID="$1"; P8="$2"
if [ -z "$KEY_ID" ] || [ -z "$P8" ] || [ ! -f "$P8" ]; then
  echo "使い方: ./setup_push.sh <キーID> <AuthKey_XXXX.p8 のパス>"; exit 1
fi
PROJECT=difframe-acae0
FB="npx --yes firebase-tools@latest"

# 1) Firebase にログイン（ブラウザが開く。まだのときだけ）
$FB login:list 2>/dev/null | grep -q "@" || $FB login

# 2) キーID（秘密ではない）と、APNs の鍵（秘密）を預ける
printf 'APNS_KEY_ID=%s\nAPNS_TEAM_ID=43346945VW\n' "$KEY_ID" > functions/.env
$FB functions:secrets:set APNS_KEY --data-file "$P8" --force --project $PROJECT

# 3) 関数とルールを公開
(cd functions && npm install --no-audit --no-fund)
$FB deploy --only functions,firestore:rules --project $PROJECT
echo "完了：プッシュ通知がサーバーから送られるようになりました"
