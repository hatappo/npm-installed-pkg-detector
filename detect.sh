#!/bin/bash

# Function to display usage
show_usage() {
    cat << EOF
Usage: $0 <list-file-path> [lock-file-path]

Arguments:
  list-file-path  File containing list of packages and versions to detect
  lock-file-path  Path to package-lock.json (default: ./package-lock.json)

List file format:
  package-name ( version1 , version2 , ... )

Examples:
  jest ( 29.7.0 , 29.6.0 )
  typescript ( 5.3.3 )
  express

Exit codes:
  0 - Normal exit (no version matches)
  1 - Error
  2 - Version matches found
EOF
}

# Initialize counter variables
total_packages=0
detected_packages=0
total_versions=0
detected_versions=0
version_match_found=0

# Check arguments
if [ $# -lt 1 ]; then
    show_usage
    exit 1
fi

LIST_FILE="$1"
LOCKFILE="${2:-./package-lock.json}"

if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed" >&2
    exit 1
fi

if [ ! -f "$LIST_FILE" ]; then
    echo "Error: List file not found: $LIST_FILE" >&2
    exit 1
fi

if [ ! -f "$LOCKFILE" ]; then
    echo "Error: package-lock.json not found: $LOCKFILE" >&2
    exit 1
fi

# Check lockfileVersion (only version 3 supported)
LOCKFILE_VERSION=$(jq -r '.lockfileVersion // empty' "$LOCKFILE" 2>/dev/null)
if [ "$LOCKFILE_VERSION" != "3" ]; then
    echo "Error: Only lockfileVersion 3 is supported (current: ${LOCKFILE_VERSION:-none})" >&2
    exit 1
fi

# Function to search for packages
search_package() {
    local pkg_name="$1"
    local pkg_versions="$2"

    # Count packages
    ((total_packages++))

    # First check package existence (regardless of version)
    local found_packages=$(jq -r --arg name "$pkg_name" '
        [
            # Check top-level dependencies and devDependencies (for lockfileVersion 2 and earlier)
            if .dependencies[$name] then
                {location: "dependencies", version: .dependencies[$name]}
            else empty end,
            if .devDependencies[$name] then
                {location: "devDependencies", version: .devDependencies[$name]}
            else empty end,
            # Check packages."" dependencies and devDependencies (for lockfileVersion 3)
            if .packages[""].dependencies[$name] then
                {location: "dependencies", version: .packages[""].dependencies[$name]}
            else empty end,
            if .packages[""].devDependencies[$name] then
                {location: "devDependencies", version: .packages[""].devDependencies[$name]}
            else empty end,
            # Check packages section
            (
                .packages | to_entries[] |
                select(.key | test("(^|/)\\Q\($name)\\E$")) |
                {location: .key, version: .value.version}
            )
        ] | unique_by(.version)
    ' "$LOCKFILE" 2>/dev/null)

    if [ -z "$found_packages" ] || [ "$found_packages" = "[]" ]; then
        if [ "$VERBOSE" = "1" ]; then
            echo "✗ $pkg_name: not detected"
        fi
        return
    fi

    # If package was found
    ((detected_packages++))
    local found_versions=$(echo "$found_packages" | jq -r '.[].version' | sort -u | tr '\n' ' ')
    echo "✓ $pkg_name: detected (target versions: $found_versions)"

    # Check specific versions
    if [ -n "$pkg_versions" ]; then
        # Split by comma and check versions
        IFS=',' read -ra VERSIONS <<< "$pkg_versions"
        for version in "${VERSIONS[@]}"; do
            # Remove leading/trailing whitespace
            version=$(echo "$version" | xargs)

            # Count total versions
            ((total_versions++))

            # Check if version exists
            local version_found=$(echo "$found_packages" | jq -r --arg v "$version" '
                .[] | select(.version == $v) | .version
            ' | head -1)

            if [ -n "$version_found" ]; then
                echo "  → Version $version: detected"
                ((detected_versions++))
                version_match_found=1
            else
                if [ "$VERBOSE" = "1" ]; then
                    echo "  → Version $version: not detected"
                fi
            fi
        done
    fi
}

# Process list file
echo "=== Configuration ==="
echo "List file: $LIST_FILE"
echo "package-lock.json: $LOCKFILE"
echo ""
echo "=== Detection Results ==="

while IFS= read -r line; do
    # Skip empty lines
    if [ -z "$line" ] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
        continue
    fi

    # Extract package name and version list
    # First check if there are parentheses
    if echo "$line" | grep -q '(.*)'  ; then
        # With version list
        pkg_name=$(echo "$line" | sed 's/[[:space:]]*(.*//' | xargs)
        pkg_versions=$(echo "$line" | sed 's/.*(\(.*\)).*/\1/')
    else
        # Package name only
        pkg_name=$(echo "$line" | xargs)
        pkg_versions=""
    fi

    # Skip if package name is empty
    if [ -z "$pkg_name" ]; then
        echo "Warning: Skipping invalid line format: $line" >&2
        continue
    fi

    search_package "$pkg_name" "$pkg_versions"
done < "$LIST_FILE"

echo ""
echo "=== Detection Summary ==="
echo "Detected packages: $detected_packages/$total_packages"
echo "Detected versions: $detected_versions/$total_versions"

# Determine exit status
if [ "$version_match_found" -eq 1 ]; then
    exit 2
else
    exit 0
fi