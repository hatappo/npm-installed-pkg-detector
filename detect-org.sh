#!/bin/bash

# Function to display usage
show_usage() {
    cat << EOF
Usage: $0 <org-name> <list-file-path>

Arguments:
  org-name        GitHub Organization name (e.g., facebook, microsoft)
  list-file-path  File containing list of packages and versions to detect

Examples:
  $0 facebook package-list.txt
  $0 microsoft vulnerable-packages.txt

Exit codes:
  0 - No detections in all repositories
  1 - Error
  2 - Detections found in one or more repositories

Environment variables:
  VERBOSE=1  Display verbose output
EOF
}

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DETECT_REMOTE_SCRIPT="$SCRIPT_DIR/detect-remote.sh"

# Check arguments
if [ $# -lt 2 ]; then
    show_usage
    exit 1
fi

ORG_NAME="$1"
LIST_FILE="$2"

# Check if detect-remote.sh exists
if [ ! -f "$DETECT_REMOTE_SCRIPT" ]; then
    printf "${RED}Error: detect-remote.sh not found: %s${NC}\n" "$DETECT_REMOTE_SCRIPT" >&2
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

echo "=== Scanning all repositories in Organization ==="
echo "Organization: $ORG_NAME"
echo "List file: $LIST_FILE"
echo ""

# Fetch repository list (max 1000)
echo "Fetching repository list..."
REPOS=$(gh repo list "$ORG_NAME" --limit 1000 --json name --jq '.[].name' 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$REPOS" ]; then
    printf "${RED}Error: Failed to fetch repository list from Organization '%s'${NC}\n" "$ORG_NAME" >&2
    echo "Please check the Organization name and access permissions" >&2
    exit 1
fi

# Count repositories
REPO_COUNT=$(echo "$REPOS" | wc -l | tr -d ' ')
echo "Detected repositories: $REPO_COUNT"
echo ""

# Arrays and variables for results
declare -a DETECTED_REPOS=()
declare -a ERROR_REPOS=()
declare -a NO_LOCKFILE_REPOS=()
PROCESSED_COUNT=0
ANY_DETECTION=0

echo "Starting processing..."
echo "========================================"

# Process each repository
while IFS= read -r repo_name; do
    ((PROCESSED_COUNT++))

    # Progress display
    echo ""
    printf "${BLUE}[%s/%s] %s/%s processing...${NC}\n" "$PROCESSED_COUNT" "$REPO_COUNT" "$ORG_NAME" "$repo_name"
    echo "----------------------------------------"

    # Run detect-remote.sh
    if [ "$VERBOSE" = "1" ]; then
        VERBOSE=1 "$DETECT_REMOTE_SCRIPT" "$ORG_NAME/$repo_name" "$LIST_FILE"
    else
        "$DETECT_REMOTE_SCRIPT" "$ORG_NAME/$repo_name" "$LIST_FILE" 2>&1 | \
            grep -E "(Detection Summary|Error|Warning:|Complete:|package-lock.json does not exist|exceeds 1MB)" || true
    fi
    EXIT_CODE=$?

    # Record results
    case $EXIT_CODE in
        0)
            # No detection (normal)
            ;;
        1)
            # Error (including missing package-lock.json)
            # Try to determine if package-lock.json is missing
            if [ "$VERBOSE" != "1" ]; then
                # Re-run briefly to check for missing package-lock.json
                ERROR_MSG=$("$DETECT_REMOTE_SCRIPT" "$ORG_NAME/$repo_name" "$LIST_FILE" 2>&1 | grep -E "(Not Found|package-lock.json does not exist)" || true)
                if [ -n "$ERROR_MSG" ]; then
                    NO_LOCKFILE_REPOS+=("$ORG_NAME/$repo_name")
                    printf "${YELLOW}  → package-lock.json does not exist${NC}\n"
                else
                    ERROR_REPOS+=("$ORG_NAME/$repo_name")
                    printf "${RED}  → Error occurred${NC}\n"
                fi
            else
                ERROR_REPOS+=("$ORG_NAME/$repo_name")
                printf "${RED}  → Error occurred${NC}\n"
            fi
            ;;
        2)
            # Version matches detected
            DETECTED_REPOS+=("$ORG_NAME/$repo_name")
            ANY_DETECTION=1
            printf "${YELLOW}  → Version matches detected!${NC}\n"
            ;;
        *)
            ERROR_REPOS+=("$ORG_NAME/$repo_name")
            printf "${RED}  → Unexpected error (exit code: %s)${NC}\n" "$EXIT_CODE"
            ;;
    esac
done <<< "$REPOS"

echo ""
echo "========================================"
echo ""

# Display summary
echo "=== Processing Summary ==="
echo "Processed repositories: $PROCESSED_COUNT/$REPO_COUNT"
echo ""

# Repositories without package-lock.json
if [ ${#NO_LOCKFILE_REPOS[@]} -gt 0 ]; then
    printf "${YELLOW}Repositories without package-lock.json: %s${NC}\n" "${#NO_LOCKFILE_REPOS[@]}"
    if [ "$VERBOSE" = "1" ]; then
        for repo in "${NO_LOCKFILE_REPOS[@]}"; do
            echo "  - $repo"
        done
    fi
    echo ""
fi

# Repositories with errors
if [ ${#ERROR_REPOS[@]} -gt 0 ]; then
    printf "${RED}Repositories with errors: %s${NC}\n" "${#ERROR_REPOS[@]}"
    for repo in "${ERROR_REPOS[@]}"; do
        echo "  - $repo"
    done
    echo ""
fi

# Repositories with detections
if [ ${#DETECTED_REPOS[@]} -gt 0 ]; then
    printf "${YELLOW}★ Repositories with version matches: %s${NC}\n" "${#DETECTED_REPOS[@]}"
    for repo in "${DETECTED_REPOS[@]}"; do
        printf "${YELLOW}  - %s${NC}\n" "$repo"
    done
    echo ""
fi

# Final results
echo "========================================"
if [ "$ANY_DETECTION" -eq 1 ]; then
    printf "${YELLOW}Warning: Target versions detected in %s repositories${NC}\n" "${#DETECTED_REPOS[@]}"
    exit 2
elif [ ${#ERROR_REPOS[@]} -gt 0 ]; then
    printf "${RED}Error: Errors occurred in %s repositories${NC}\n" "${#ERROR_REPOS[@]}"
    exit 1
else
    printf "${GREEN}Complete: No target versions detected in all repositories${NC}\n"
    exit 0
fi