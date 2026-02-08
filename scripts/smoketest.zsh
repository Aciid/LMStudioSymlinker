#!/usr/bin/env zsh
# Smoketest for LM Studio Symlinker — run in a fresh VM to verify build and environment.
# Usage: ./scripts/smoketest.zsh [--full]
#   --full  Also build release binary and .app bundle (slower, exercises build-app.sh).
# Run from repo root or from scripts/; requires zsh, macOS 15+, Swift 6.

setopt LOCAL_OPTIONS ERR_EXIT
unsetopt GLOB_DOTS

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

FULL=
for arg in "${@}"; do
  if [[ "$arg" == --full ]]; then FULL=1; fi
done

echo "=== LM Studio Symlinker smoketest ==="
echo "Repo root: $REPO_ROOT"
echo ""

# --- 1. Must be macOS (Darwin) ---
if [[ "$(uname -s)" != Darwin ]]; then
  echo "FAIL: This project requires macOS (Darwin). Current OS: $(uname -s)"
  exit 1
fi
echo "OK: macOS (Darwin)"

# --- 2. Swift must be available ---
if ! command -v swift >/dev/null 2>&1; then
  echo "FAIL: 'swift' not found. Install Xcode or the Swift toolchain for macOS."
  exit 1
fi
echo "OK: swift found"

# --- 3. Swift 6 required (Package.swift: swift-tools-version: 6.0) ---
SWIFT_VERSION=$(swift --version 2>/dev/null | head -1)
if ! swift --version 2>/dev/null | grep -q "Swift version 6"; then
  echo "FAIL: Swift 6 is required. Found: $SWIFT_VERSION"
  exit 1
fi
echo "OK: Swift 6 ($SWIFT_VERSION)"

# --- 4. Optional: macOS 15+ (Sequoia) — warn only on older ---
OSVER=$(uname -r)
# Darwin 24.x = macOS 15 (Sequoia). Earlier = older macOS.
if [[ "${OSVER%%.*}" -lt 24 ]]; then
  echo "WARN: This app targets macOS 15 (Sequoia). You are on $(sw_vers -productVersion). Build may still work."
fi

# --- 5. Debug build ---
echo ""
echo "--- Debug build (swift build) ---"
swift build
if [[ ! -f "$REPO_ROOT/.build/debug/LMStudioSymlinker" ]]; then
  echo "FAIL: Debug executable not found at .build/debug/LMStudioSymlinker"
  exit 1
fi
echo "OK: Debug build succeeded"

# --- 6. Optional: release build + .app bundle ---
if [[ -n "$FULL" ]]; then
  echo ""
  echo "--- Release build (swift build -c release) ---"
  swift build -c release
  if [[ ! -f "$REPO_ROOT/.build/release/LMStudioSymlinker" ]]; then
    echo "FAIL: Release executable not found"
    exit 1
  fi
  echo "OK: Release build succeeded"
  echo ""
  echo "--- App bundle (./scripts/build-app.sh) ---"
  "$REPO_ROOT/scripts/build-app.sh"
  if [[ ! -d "$REPO_ROOT/build/LMStudioSymlinker.app" ]]; then
    echo "FAIL: build/LMStudioSymlinker.app not found"
    exit 1
  fi
  echo "OK: App bundle created"
fi

echo ""
echo "=== Smoketest passed ==="
exit 0
