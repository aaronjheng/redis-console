#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/apple/swift-nio-ssh.git"
VENDOR_DIR="Vendor/swift-nio-ssh"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_DIR="$SCRIPT_DIR"
BARE_REPO="/tmp/swift-nio-ssh-bare"

usage() {
    cat <<EOF
Usage: $0 [list|update <tag>]

Commands:
  list        List available upstream tags
  update TAG  Update vendor to specified tag (e.g. 0.13.0)

Examples:
  $0 list
  $0 update 0.14.0
EOF
    exit 1
}

ensure_bare_repo() {
    if [[ -d "$BARE_REPO" ]]; then
        git -C "$BARE_REPO" fetch --tags 2>/dev/null || true
    else
        echo "Cloning upstream repo (first time only)..."
        git clone --bare "$REPO" "$BARE_REPO"
    fi
}

list_tags() {
    ensure_bare_repo
    echo "Available tags:"
    git -C "$BARE_REPO" tag -l --sort=version:refname | tail -10
}

apply_patches() {
    [[ -d "$PATCH_DIR" ]] || return

    local count=0
    for f in "$PATCH_DIR"/*.patch; do
        [[ -f "$f" ]] || continue
        local name
        name=$(basename "$f" .patch)
        echo "Applying: $name"

        local target
        target=$(grep '^--- a/' "$f" | head -1 | sed 's|^--- a/||')
        local full="$VENDOR_DIR/$target"

        if [[ ! -f "$full" ]]; then
            echo "Error: target file not found: $full"
            exit 1
        fi

        if patch -p1 "$full" < "$f"; then
            count=$((count + 1))
        else
            echo "Error: failed to apply $name"
            exit 1
        fi
    done
    echo "Applied $count patch(es)"
}

update_vendor() {
    local target_tag="$1"

    ensure_bare_repo

    if ! git -C "$BARE_REPO" rev-parse "$target_tag" >/dev/null 2>&1; then
        echo "Error: tag '$target_tag' not found"
        exit 1
    fi

    local cur
    cur=$(grep -m1 'swift-tools-version:' "$VENDOR_DIR/Package.swift" 2>/dev/null | sed 's/.*swift-tools-version:\([0-9.]*\).*/\1/' || echo "unknown")
    echo "Current swift-tools-version: ${cur}"
    echo "Target version:              $target_tag"

    echo "Removing old sources..."
    rm -rf "$VENDOR_DIR"/*
    rm -rf "$VENDOR_DIR"/.[!.]*

    echo "Extracting $target_tag..."
    git -C "$BARE_REPO" archive "$target_tag" | tar -C "$VENDOR_DIR" -xf -

    apply_patches

    echo "Verifying build..."
    if swift build --package-path "$VENDOR_DIR" 2>&1 | tail -5 | grep -q "build complete"; then
        echo "Build OK"
    else
        echo "Warning: build verification failed, please check manually"
    fi

    echo ""
    echo "Done! Updated to $target_tag"
    echo ""
    echo "Next steps:"
    echo "  1. Review: git diff --stat"
    echo "  2. Commit: git add Vendor/ && git commit -m 'Update swift-nio-ssh to $target_tag'"
}

# --- Main ---

[[ $# -lt 1 ]] && usage

case "$1" in
    list)  list_tags ;;
    update)
        [[ $# -lt 2 ]] && { echo "Error: TAG required"; usage; }
        update_vendor "$2"
        ;;
    *) usage ;;
esac
