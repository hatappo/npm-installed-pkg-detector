#!/bin/bash

# 使用方法を表示する関数
show_usage() {
    cat << EOF
使用方法: $0 <org-name> <list-file-path>

引数:
  org-name        GitHub Organization名 (例: facebook, microsoft)
  list-file-path  検出対象のパッケージとバージョンの一覧ファイル

例:
  $0 facebook package-list.txt
  $0 microsoft vulnerable-packages.txt

終了コード:
  0 - すべてのリポジトリで検出なし
  1 - エラー
  2 - 1つ以上のリポジトリで検出あり

環境変数:
  VERBOSE=1  詳細な出力を表示
EOF
}

# カラーコード
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# スクリプトのディレクトリパス
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DETECT_REMOTE_SCRIPT="$SCRIPT_DIR/detect-remote.sh"

# 引数チェック
if [ $# -lt 2 ]; then
    show_usage
    exit 1
fi

ORG_NAME="$1"
LIST_FILE="$2"

# detect-remote.sh の存在確認
if [ ! -f "$DETECT_REMOTE_SCRIPT" ]; then
    printf "${RED}エラー: detect-remote.sh が見つかりません: %s${NC}\n" "$DETECT_REMOTE_SCRIPT" >&2
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

echo "=== Organization 全体のリポジトリをスキャン ==="
echo "Organization: $ORG_NAME"
echo "リストファイル: $LIST_FILE"
echo ""

# リポジトリ一覧を取得（最大1000件）
echo "リポジトリ一覧を取得中..."
REPOS=$(gh repo list "$ORG_NAME" --limit 1000 --json name --jq '.[].name' 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$REPOS" ]; then
    printf "${RED}エラー: Organization '%s' のリポジトリ一覧を取得できませんでした${NC}\n" "$ORG_NAME" >&2
    echo "Organization名が正しいか、アクセス権限があるか確認してください" >&2
    exit 1
fi

# リポジトリ数をカウント
REPO_COUNT=$(echo "$REPOS" | wc -l | tr -d ' ')
echo "検出されたリポジトリ数: $REPO_COUNT"
echo ""

# 結果を格納する配列と変数
declare -a DETECTED_REPOS=()
declare -a ERROR_REPOS=()
declare -a NO_LOCKFILE_REPOS=()
PROCESSED_COUNT=0
ANY_DETECTION=0

echo "処理を開始します..."
echo "========================================"

# 各リポジトリを処理
while IFS= read -r repo_name; do
    ((PROCESSED_COUNT++))

    # 進捗表示
    echo ""
    printf "${BLUE}[%s/%s] %s/%s を処理中...${NC}\n" "$PROCESSED_COUNT" "$REPO_COUNT" "$ORG_NAME" "$repo_name"
    echo "----------------------------------------"

    # detect-remote.sh を実行
    if [ "$VERBOSE" = "1" ]; then
        VERBOSE=1 "$DETECT_REMOTE_SCRIPT" "$ORG_NAME/$repo_name" "$LIST_FILE"
    else
        "$DETECT_REMOTE_SCRIPT" "$ORG_NAME/$repo_name" "$LIST_FILE" 2>&1 | \
            grep -E "(検出結果サマリ|エラー|警告:|完了:|package-lock.json が存在しません|1MB を超える)" || true
    fi
    EXIT_CODE=$?

    # 結果の記録
    case $EXIT_CODE in
        0)
            # 検出なし（正常）
            ;;
        1)
            # エラー（package-lock.jsonが無い場合を含む）
            # エラーメッセージから判断
            if [ "$VERBOSE" != "1" ]; then
                # 簡易的に再実行してpackage-lock.json不在を確認
                ERROR_MSG=$("$DETECT_REMOTE_SCRIPT" "$ORG_NAME/$repo_name" "$LIST_FILE" 2>&1 | grep -E "(Not Found|package-lock.json が存在しません)" || true)
                if [ -n "$ERROR_MSG" ]; then
                    NO_LOCKFILE_REPOS+=("$ORG_NAME/$repo_name")
                    printf "${YELLOW}  → package-lock.json が存在しません${NC}\n"
                else
                    ERROR_REPOS+=("$ORG_NAME/$repo_name")
                    printf "${RED}  → エラーが発生しました${NC}\n"
                fi
            else
                ERROR_REPOS+=("$ORG_NAME/$repo_name")
                printf "${RED}  → エラーが発生しました${NC}\n"
            fi
            ;;
        2)
            # バージョン一致が検出された
            DETECTED_REPOS+=("$ORG_NAME/$repo_name")
            ANY_DETECTION=1
            printf "${YELLOW}  → バージョン一致が検出されました！${NC}\n"
            ;;
        *)
            ERROR_REPOS+=("$ORG_NAME/$repo_name")
            printf "${RED}  → 予期しないエラー（終了コード: %s）${NC}\n" "$EXIT_CODE"
            ;;
    esac
done <<< "$REPOS"

echo ""
echo "========================================"
echo ""

# サマリーを表示
echo "=== 処理結果サマリー ==="
echo "処理済みリポジトリ数: $PROCESSED_COUNT/$REPO_COUNT"
echo ""

# package-lock.jsonが無いリポジトリ
if [ ${#NO_LOCKFILE_REPOS[@]} -gt 0 ]; then
    printf "${YELLOW}package-lock.json が無いリポジトリ: %s件${NC}\n" "${#NO_LOCKFILE_REPOS[@]}"
    if [ "$VERBOSE" = "1" ]; then
        for repo in "${NO_LOCKFILE_REPOS[@]}"; do
            echo "  - $repo"
        done
    fi
    echo ""
fi

# エラーが発生したリポジトリ
if [ ${#ERROR_REPOS[@]} -gt 0 ]; then
    printf "${RED}エラーが発生したリポジトリ: %s件${NC}\n" "${#ERROR_REPOS[@]}"
    for repo in "${ERROR_REPOS[@]}"; do
        echo "  - $repo"
    done
    echo ""
fi

# 検出があったリポジトリ
if [ ${#DETECTED_REPOS[@]} -gt 0 ]; then
    printf "${YELLOW}★ バージョン一致が検出されたリポジトリ: %s件${NC}\n" "${#DETECTED_REPOS[@]}"
    for repo in "${DETECTED_REPOS[@]}"; do
        printf "${YELLOW}  - %s${NC}\n" "$repo"
    done
    echo ""
fi

# 最終結果
echo "========================================"
if [ "$ANY_DETECTION" -eq 1 ]; then
    printf "${YELLOW}警告: %s 個のリポジトリで対象バージョンが検出されました${NC}\n" "${#DETECTED_REPOS[@]}"
    exit 2
elif [ ${#ERROR_REPOS[@]} -gt 0 ]; then
    printf "${RED}エラー: %s 個のリポジトリでエラーが発生しました${NC}\n" "${#ERROR_REPOS[@]}"
    exit 1
else
    printf "${GREEN}完了: すべてのリポジトリで対象バージョンは検出されませんでした${NC}\n"
    exit 0
fi