#!/usr/bin/env bash
# Unjank installer — https://github.com/no-hup/unjank
# Usage: curl -fsSL https://raw.githubusercontent.com/no-hup/unjank/main/install.sh | bash
set -euo pipefail

REPO="no-hup/unjank"
BRANCH="main"
SKILLS=("perf-setup" "perf-query" "perf-dashboard" "perf-fix")
TARGET_DIR=".claude/skills"

# ─── Preflight checks ───────────────────────────────────────────────
if [ ! -d ".git" ]; then
  echo "Error: Run this from the root of your project (no .git directory found)."
  exit 1
fi

if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
  echo "Error: curl or wget is required."
  exit 1
fi

if command -v git &>/dev/null; then
  USE_GIT=true
else
  USE_GIT=false
fi

# ─── Anonymous install counter (transparent & optional) ──────────────
# This pings a public counter so the maintainer knows how many people
# use Unjank. It sends NO personal data — just increments a number.
# To skip: curl ... | UNJANK_NO_ANALYTICS=1 bash
if [ -z "${UNJANK_NO_ANALYTICS:-}" ]; then
  curl -fsSL "https://hits.sh/github.com/no-hup/unjank/install.svg" >/dev/null 2>&1 || true
fi

# ─── Install ─────────────────────────────────────────────────────────
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Installing Unjank skills..."

if $USE_GIT; then
  git clone --depth 1 --branch "$BRANCH" "https://github.com/$REPO.git" "$TMPDIR/unjank" 2>/dev/null
else
  curl -fsSL "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" | tar -xz -C "$TMPDIR"
  mv "$TMPDIR/unjank-$BRANCH" "$TMPDIR/unjank"
fi

mkdir -p "$TARGET_DIR"

for skill in "${SKILLS[@]}"; do
  if [ -d "$TARGET_DIR/$skill" ]; then
    echo "  Updating $skill..."
    rm -rf "$TARGET_DIR/$skill"
  else
    echo "  Installing $skill..."
  fi
  cp -r "$TMPDIR/unjank/skills/$skill" "$TARGET_DIR/$skill"
done

# ─── Done ────────────────────────────────────────────────────────────
echo ""
echo "Unjank installed to $TARGET_DIR/"
echo ""
echo "IMPORTANT: Restart Claude Code (or start a new conversation) for the"
echo "skills to register as slash commands (/perf-setup, /perf-query, etc.)"
echo ""
echo "Next steps:"
echo "  1. Restart Claude Code or start a new conversation"
echo "  2. Run: /perf-setup (it will handle gcloud auth and everything else)"
echo ""
echo "Full docs: https://github.com/$REPO"
