#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GAME_DIR="$REPO_ROOT/game"
OUT_DIR="$SCRIPT_DIR/public"
CACHE_DIR="${HOME}/.cache/ai-town-godot"
GODOT_VERSION="4.7"
GODOT_STATUS="stable"
GODOT_TEMPLATE_DIR="4.7.stable"
CHUNK_BYTES=$((20 * 1024 * 1024))

mkdir -p "$CACHE_DIR"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

GODOT_ZIP="$CACHE_DIR/godot-${GODOT_VERSION}.zip"
GODOT_HOME="$CACHE_DIR/godot-${GODOT_VERSION}"
GODOT_BIN=""

if [[ -d "$GODOT_HOME" ]]; then
  GODOT_BIN="$(find "$GODOT_HOME" -maxdepth 1 -type f -name 'Godot_*linux.x86_64' | head -n 1 || true)"
fi

if [[ -z "$GODOT_BIN" || ! -x "$GODOT_BIN" ]]; then
  echo "Downloading Godot ${GODOT_VERSION}..."
  curl --fail --location --retry 3 \
    "https://downloads.godotengine.org/?version=${GODOT_VERSION}&flavor=${GODOT_STATUS}&slug=linux.x86_64.zip&platform=linux.64" \
    --output "$GODOT_ZIP"
  rm -rf "$GODOT_HOME"
  mkdir -p "$GODOT_HOME"
  unzip -q "$GODOT_ZIP" -d "$GODOT_HOME"
  GODOT_BIN="$(find "$GODOT_HOME" -maxdepth 1 -type f -name 'Godot_*linux.x86_64' | head -n 1)"
  chmod +x "$GODOT_BIN"
fi

TEMPLATE_TARGET="$HOME/.local/share/godot/export_templates/${GODOT_TEMPLATE_DIR}"
if [[ ! -f "$TEMPLATE_TARGET/web_release.zip" ]]; then
  echo "Downloading Godot export templates..."
  TEMPLATE_TPZ="$CACHE_DIR/export_templates-${GODOT_VERSION}.tpz"
  TEMPLATE_TMP="$CACHE_DIR/export_templates-${GODOT_VERSION}"
  curl --fail --location --retry 3 \
    "https://downloads.godotengine.org/?version=${GODOT_VERSION}&flavor=${GODOT_STATUS}&slug=export_templates.tpz&platform=templates" \
    --output "$TEMPLATE_TPZ"
  rm -rf "$TEMPLATE_TMP"
  mkdir -p "$TEMPLATE_TMP"
  unzip -q "$TEMPLATE_TPZ" -d "$TEMPLATE_TMP"
  mkdir -p "$TEMPLATE_TARGET"
  cp -a "$TEMPLATE_TMP/templates/." "$TEMPLATE_TARGET/"
fi

"$GODOT_BIN" --version

echo "Importing Godot resources..."
"$GODOT_BIN" --headless --path "$GAME_DIR" --import

echo "Exporting Web release..."
"$GODOT_BIN" --headless --path "$GAME_DIR" --export-release "Web" "$OUT_DIR/index.html"

test -f "$OUT_DIR/index.html"
test -f "$OUT_DIR/index.js"
test -f "$OUT_DIR/index.wasm"
test -f "$OUT_DIR/index.pck"

chunk_large_asset() {
  local file="$1"
  local content_type="$2"
  local filename
  filename="$(basename "$file")"

  local original_size encoded_size sha256 compressed prefix manifest
  original_size="$(stat -c%s "$file")"
  sha256="$(sha256sum "$file" | awk '{print $1}')"
  compressed="$OUT_DIR/.${filename}.gzip"
  prefix="$OUT_DIR/${filename}.chunk."
  manifest="$OUT_DIR/${filename}.parts.json"

  echo "Compressing ${filename}..."
  gzip -9 -c "$file" > "$compressed"
  encoded_size="$(stat -c%s "$compressed")"

  split -b "$CHUNK_BYTES" -d -a 3 --additional-suffix=.bin "$compressed" "$prefix"
  rm -f "$compressed" "$file"

  python3 - "$OUT_DIR" "$filename" "$content_type" "$original_size" "$encoded_size" "$sha256" "$manifest" <<'PY'
import glob
import json
import os
import sys

out_dir, filename, content_type, original_size, encoded_size, sha256, manifest_path = sys.argv[1:]
parts = sorted(glob.glob(os.path.join(out_dir, f"{filename}.chunk.*.bin")))
if not parts:
    raise SystemExit(f"No chunks generated for {filename}")

payload = {
    "version": 1,
    "contentType": content_type,
    "contentEncoding": "gzip",
    "originalSize": int(original_size),
    "encodedSize": int(encoded_size),
    "sha256": sha256,
    "parts": [os.path.basename(path) for path in parts],
}
with open(manifest_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, separators=(",", ":"))
PY

  mapfile -t parts < <(find "$OUT_DIR" -maxdepth 1 -type f -name "${filename}.chunk.*.bin" | sort)
  if (( ${#parts[@]} == 0 )); then
    echo "No chunks found for ${filename}" >&2
    exit 21
  fi

  for part in "${parts[@]}"; do
    local size
    size="$(stat -c%s "$part")"
    if (( size >= 25 * 1024 * 1024 )); then
      echo "Chunk exceeds Cloudflare 25 MiB limit: $part ($size bytes)" >&2
      exit 22
    fi
  done

  cat "${parts[@]}" | gzip -t
  echo "${filename}: original=${original_size} encoded=${encoded_size} chunks=${#parts[@]}"
}

chunk_large_asset "$OUT_DIR/index.wasm" "application/wasm"
chunk_large_asset "$OUT_DIR/index.pck" "application/octet-stream"

# Keep generated deploy assets out of source-control oriented tooling.
printf '%s\n' "${GITHUB_SHA:-unknown}" > "$OUT_DIR/build-commit.txt"

echo "Largest deploy assets:"
find "$OUT_DIR" -type f -printf '%s %p\n' \
  | sort -nr \
  | head -n 20 \
  | numfmt --field=1 --to=iec-i --suffix=B

if find "$OUT_DIR" -type f -size +$((25 * 1024 * 1024 - 1))c -print -quit | grep -q .; then
  echo "At least one generated static asset still reaches or exceeds 25 MiB." >&2
  exit 23
fi

echo "Godot Web build is ready for Cloudflare Static Assets."
