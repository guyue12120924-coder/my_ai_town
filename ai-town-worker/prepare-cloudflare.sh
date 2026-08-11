#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$SCRIPT_DIR/public"
TMP_DIR="${TMPDIR:-/tmp}/ai-town-web-dist"
DIST_URL="https://codeload.github.com/guyue12120924-coder/my_ai_town/tar.gz/refs/heads/web-dist"

validate_dist() {
  test -f "$OUT_DIR/index.html" \
    && test -f "$OUT_DIR/index.js" \
    && test -f "$OUT_DIR/index.wasm.parts.json" \
    && test -f "$OUT_DIR/index.pck.parts.json"
}

if [[ "${WORKERS_CI:-0}" == "1" ]]; then
  echo "Workers Builds detected. Trying prebuilt web-dist assets first..."
  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"

  if curl --fail --location --retry 2 --connect-timeout 15 \
      "$DIST_URL?build=${WORKERS_CI_COMMIT_SHA:-latest}" \
      --output "$TMP_DIR/web-dist.tar.gz"; then
    mkdir -p "$TMP_DIR/extracted"
    if tar -xzf "$TMP_DIR/web-dist.tar.gz" -C "$TMP_DIR/extracted" --strip-components=1; then
      DIST_PUBLIC="$TMP_DIR/extracted/ai-town-worker/public"
      if [[ -d "$DIST_PUBLIC" ]]; then
        rm -rf "$OUT_DIR"
        mkdir -p "$OUT_DIR"
        cp -a "$DIST_PUBLIC/." "$OUT_DIR/"
        if validate_dist; then
          echo "Using prebuilt web-dist assets. Godot export skipped."
          exit 0
        fi
      fi
    fi
  fi

  echo "No usable web-dist yet; falling back to one full Godot export."
fi

exec bash "$SCRIPT_DIR/build-web.sh"
