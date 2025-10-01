#!/bin/bash

# 使用方法を表示する関数
show_usage() {
    cat << EOF
使用方法: $0 <org/repo> <list-file-path>

引数:
  org/repo        GitHubリポジトリ (例: facebook/react)
  list-file-path  検出対象のパッケージとバージョンの一覧ファイル

例:
  $0 facebook/react package-list.txt

終了コード:
  0 - 正常終了（バージョン一致なし）
  1 - エラー
  2 - バージョン一致あり
EOF
}

# カラーコード
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# スクリプトのディレクトリパス
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DETECT_SCRIPT="$SCRIPT_DIR/detect.sh"
WORK_DIR="$SCRIPT_DIR/work"

# 引数チェック
if [ $# -lt 2 ]; then
    show_usage
    exit 1
fi

REPO="$1"
LIST_FILE="$2"

# detect.sh の存在確認
if [ ! -f "$DETECT_SCRIPT" ]; then
    printf "${RED}エラー: detect.sh が見つかりません: $DETECT_SCRIPT${NC}\n" >&2
    exit 1
fi

# 必要なコマンドの確認
if ! command -v gh &> /dev/null; then
    printf "${RED}エラー: GitHub CLI (gh) がインストールされていません${NC}\n" >&2
    echo "インストール方法: https://cli.github.com/" >&2
    exit 1
fi

if ! command -v jq &> /dev/null; then
    printf "${RED}エラー: jq がインストールされていません${NC}\n" >&2
    exit 1
fi

if ! command -v base64 &> /dev/null; then
    printf "${RED}エラー: base64 コマンドが利用できません${NC}\n" >&2
    exit 1
fi

# work ディレクトリの作成
mkdir -p "$WORK_DIR"

echo "=== リモートリポジトリの package-lock.json を検出 ==="
echo "リポジトリ: $REPO"
echo "リストファイル: $LIST_FILE"
echo ""

# 一時ファイル
GH_RESPONSE="$WORK_DIR/gh-response-$$.json"
LOCK_FILE="$WORK_DIR/package-lock-$$.json"

# クリーンアップ関数
cleanup() {
    rm -f "$GH_RESPONSE" "$LOCK_FILE"
}

# 実行前の念のためのクリーンアップと終了時のクリーンアップ設定
cleanup
trap cleanup EXIT

echo "GitHub API から package-lock.json を取得中..."

# GitHub API を使用してファイルを取得
if ! gh api "repos/${REPO}/contents/package-lock.json" > "$GH_RESPONSE" 2>&1; then
    printf "${RED}エラー: GitHub API からファイルを取得できませんでした${NC}\n" >&2
    echo "詳細: $(cat "$GH_RESPONSE")" >&2
    exit 1
fi

# レスポンスのタイプを確認
RESPONSE_TYPE=$(jq -r 'type' "$GH_RESPONSE" 2>/dev/null)
if [ "$RESPONSE_TYPE" != "object" ]; then
    printf "${RED}エラー: 予期しない API レスポンス形式${NC}\n" >&2
    exit 1
fi

# エラーレスポンスのチェック
if jq -e '.message' "$GH_RESPONSE" &>/dev/null; then
    ERROR_MSG=$(jq -r '.message' "$GH_RESPONSE")
    printf "${RED}エラー: %s${NC}\n" "$ERROR_MSG" >&2
    if [ "$ERROR_MSG" = "Not Found" ]; then
        echo "リポジトリまたは package-lock.json が存在しません" >&2
    fi
    exit 1
fi

# content フィールドの存在確認
if ! jq -e '.content' "$GH_RESPONSE" &>/dev/null; then
    printf "${RED}エラー: content フィールドが見つかりません${NC}\n" >&2
    echo "ファイルが大きすぎる可能性があります（GitHub API は 1MB までのファイルをサポート）" >&2
    exit 1
fi

# ファイルサイズの取得と表示
FILE_SIZE=$(jq -r '.size // "不明"' "$GH_RESPONSE")
echo "ファイルサイズ: $FILE_SIZE bytes"

echo "package-lock.json をデコード中..."

# base64 デコード（改行を削除してからデコード）
if ! jq -r '.content' "$GH_RESPONSE" | tr -d '\n' | base64 --decode > "$LOCK_FILE" 2>/dev/null; then
    printf "${RED}エラー: base64 デコードに失敗しました${NC}\n" >&2
    exit 1
fi

# デコード後のファイルサイズ確認
if [ ! -s "$LOCK_FILE" ]; then
    printf "${RED}エラー: デコード後のファイルが空です${NC}\n" >&2
    exit 1
fi

echo ""
echo "detect.sh を実行中..."
echo "----------------------------------------"

# detect.sh を実行（VERBOSE 環境変数を引き継ぐ）
"$DETECT_SCRIPT" "$LIST_FILE" "$LOCK_FILE"
EXIT_CODE=$?

echo "----------------------------------------"
echo ""

# 結果の表示
case $EXIT_CODE in
    0)
        printf "${GREEN}完了: バージョン一致なし${NC}\n"
        ;;
    1)
        printf "${RED}エラー: detect.sh でエラーが発生しました${NC}\n"
        ;;
    2)
        printf "${YELLOW}警告: バージョン一致が検出されました${NC}\n"
        ;;
    *)
        printf "${RED}予期しない終了コード: %s${NC}\n" "$EXIT_CODE"
        ;;
esac

exit $EXIT_CODE
