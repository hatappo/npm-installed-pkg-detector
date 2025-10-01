#!/bin/bash

# Function to display usage
show_usage() {
    cat << EOF
Usage: $0 <org/repo> <list-file-path>

Arguments:
  org/repo        GitHub repository (e.g., facebook/react)
  list-file-path  File containing list of packages and versions to detect

Example:
  $0 facebook/react package-list.txt

Requirements:
  - gh (GitHub CLI) must be installed and authenticated
  - jq must be installed
  - base64 command must be available

Exit codes:
  0 - Normal exit (no version matches)
  1 - Error
  2 - Version matches found
EOF
}

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DETECT_SCRIPT="$SCRIPT_DIR/detect.sh"
WORK_DIR="$SCRIPT_DIR/work"

# Check arguments
if [ $# -lt 2 ]; then
    show_usage
    exit 1
fi

REPO="$1"
LIST_FILE="$2"

# Check if detect.sh exists
if [ ! -f "$DETECT_SCRIPT" ]; then
    printf "${RED}Error: detect.sh not found: $DETECT_SCRIPT${NC}\n" >&2
    exit 1
fi

# Check required commands
if ! command -v gh &> /dev/null; then
    printf "${RED}Error: GitHub CLI (gh) is not installed${NC}\n" >&2
    echo "Installation: https://cli.github.com/" >&2
    exit 1
fi

if ! command -v jq &> /dev/null; then
    printf "${RED}Error: jq is not installed${NC}\n" >&2
    exit 1
fi

if ! command -v base64 &> /dev/null; then
    printf "${RED}Error: base64 command is not available${NC}\n" >&2
    exit 1
fi

# Create work directory
mkdir -p "$WORK_DIR"

echo "=== Detecting package-lock.json from remote repository ==="
echo "Repository: $REPO"
echo "List file: $LIST_FILE"
echo ""

# Temporary files
GH_RESPONSE="$WORK_DIR/gh-response-$$.json"
LOCK_FILE="$WORK_DIR/package-lock-$$.json"

# Cleanup function
cleanup() {
    rm -f "$GH_RESPONSE" "$LOCK_FILE"
}

# Pre-execution cleanup and exit cleanup setup
cleanup
trap cleanup EXIT

echo "Fetching package-lock.json from GitHub API..."

# Fetch file using GitHub API
if ! gh api "repos/${REPO}/contents/package-lock.json" > "$GH_RESPONSE" 2>&1; then
    printf "${RED}Error: Failed to fetch file from GitHub API${NC}\n" >&2
    echo "Details: $(cat "$GH_RESPONSE")" >&2
    exit 1
fi

# Check response type
RESPONSE_TYPE=$(jq -r 'type' "$GH_RESPONSE" 2>/dev/null)
if [ "$RESPONSE_TYPE" != "object" ]; then
    printf "${RED}Error: Unexpected API response format${NC}\n" >&2
    exit 1
fi

# Check for error response
if jq -e '.message' "$GH_RESPONSE" &>/dev/null; then
    ERROR_MSG=$(jq -r '.message' "$GH_RESPONSE")
    printf "${RED}Error: %s${NC}\n" "$ERROR_MSG" >&2
    if [ "$ERROR_MSG" = "Not Found" ]; then
        echo "Repository or package-lock.json does not exist" >&2
    fi
    exit 1
fi

# Check for content field
if ! jq -e '.content' "$GH_RESPONSE" &>/dev/null; then
    printf "${RED}Error: content field not found${NC}\n" >&2
    echo "File may be too large (GitHub API supports files up to 1MB)" >&2
    exit 1
fi

# Get and display file size
FILE_SIZE=$(jq -r '.size // "unknown"' "$GH_RESPONSE")
echo "File size: $FILE_SIZE bytes"

echo "Decoding package-lock.json..."

# Base64 decode (remove newlines before decoding)
if ! jq -r '.content' "$GH_RESPONSE" | tr -d '\n' | base64 --decode > "$LOCK_FILE" 2>/dev/null; then
    printf "${RED}Error: base64 decode failed${NC}\n" >&2
    exit 1
fi

# Check decoded file size
if [ ! -s "$LOCK_FILE" ]; then
    printf "${RED}Error: Decoded file is empty${NC}\n" >&2
    exit 1
fi

echo ""
echo "Running detect.sh..."
echo "----------------------------------------"

# Run detect.sh (inherit VERBOSE environment variable)
"$DETECT_SCRIPT" "$LIST_FILE" "$LOCK_FILE"
EXIT_CODE=$?

echo "----------------------------------------"
echo ""

# Display results
case $EXIT_CODE in
    0)
        printf "${GREEN}Complete: No version matches${NC}\n"
        ;;
    1)
        printf "${RED}Error: detect.sh encountered an error${NC}\n"
        ;;
    2)
        printf "${YELLOW}Warning: Version matches detected${NC}\n"
        ;;
    *)
        printf "${RED}Unexpected exit code: %s${NC}\n" "$EXIT_CODE"
        ;;
esac

exit $EXIT_CODE