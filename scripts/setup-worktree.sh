#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PARENT_DIR="$(dirname "$ROOT_DIR")"
MAIN_DIR="$(git -C "$ROOT_DIR" worktree list --porcelain | head -n 1 | sed 's/^worktree //')"
MAIN_PARENT_DIR="$(dirname "$MAIN_DIR")"

for package in account-av apps-av; do
  if [ ! -e "$PARENT_DIR/$package" ]; then
    if [ ! -d "$MAIN_PARENT_DIR/$package" ]; then
      echo "setup-worktree: $MAIN_PARENT_DIR/$package is missing; clone miguelavalos/$package beside the main checkout" >&2
      exit 1
    fi
    ln -s "$MAIN_PARENT_DIR/$package" "$PARENT_DIR/$package"
  fi
done

for app in ios macos; do
  (cd "$ROOT_DIR/apps/$app" && xcodegen generate --quiet)
done

echo "setup-worktree: linked account-av and apps-av, generated apps/ios and apps/macos projects"
