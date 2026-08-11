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

  local original_size sha256 prefix manifest
  original_size="$(stat -c%s "$file")"
  sha256="$(sha256sum "$file" | awk '{print $1}')"
  prefix="$OUT_DIR/${filename}.chunk."
  manifest="$OUT_DIR/${filename}.parts.json"

  echo "Splitting raw ${filename} into Cloudflare-safe chunks..."
  split -b "$CHUNK_BYTES" -d -a 3 --additional-suffix=.bin "$file" "$prefix"
  rm -f "$file"

  python3 - "$OUT_DIR" "$filename" "$content_type" "$original_size" "$sha256" "$manifest" <<'PY'
import glob
import json
import os
import sys

out_dir, filename, content_type, original_size, sha256, manifest_path = sys.argv[1:]
parts = sorted(glob.glob(os.path.join(out_dir, f"{filename}.chunk.*.bin")))
if not parts:
    raise SystemExit(f"No chunks generated for {filename}")

payload = {
    "version": 2,
    "contentType": content_type,
    "contentEncoding": "identity",
    "originalSize": int(original_size),
    "encodedSize": int(original_size),
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

  local rebuilt_sha
  rebuilt_sha="$(cat "${parts[@]}" | sha256sum | awk '{print $1}')"
  if [[ "$rebuilt_sha" != "$sha256" ]]; then
    echo "Chunk reassembly checksum mismatch for ${filename}" >&2
    exit 24
  fi

  echo "${filename}: raw=${original_size} bytes chunks=${#parts[@]} sha256=${sha256}"
}

chunk_large_asset "$OUT_DIR/index.wasm" "application/wasm"
chunk_large_asset "$OUT_DIR/index.pck" "application/octet-stream"

echo "Patching Godot HTML for chunked PCK loading and browser input..."
python3 - "$OUT_DIR/index.html" <<'PY'
from pathlib import Path
import re
import sys

html_path = Path(sys.argv[1])
html = html_path.read_text(encoding="utf-8")

# Godot's Adaptive policy is the only owner of the canvas backing size and CSS
# geometry. Never assign canvas.width/height from page JavaScript: doing so
# bypasses Godot's resize notification and separates rendering from input.
interaction_css = r'''
html, body {
	background: #152d25 !important;
}

#canvas {
	background: #152d25 !important;
	pointer-events: auto !important;
}

#status {
	pointer-events: none;
}
'''
style_marker = "\t\t</style>"
if style_marker not in html:
    raise SystemExit("Could not find Godot style block while patching web input CSS")
html = html.replace(style_marker, interaction_css + "\n" + style_marker, 1)

pattern = re.compile(
    r"\t\tsetStatusMode\('progress'\);\n"
    r"\t\tengine\.startGame\(\{\n.*?\n"
    r"\t\t\}\)\.then\(\(\) => \{\n"
    r"\t\t\tsetStatusMode\('hidden'\);\n"
    r"\t\t\}, displayFailureNotice\);",
    re.S,
)
replacement = r'''\t\tsetStatusMode('progress');

\t\tconst canvas = document.getElementById('canvas');
\t\tif (canvas) {
\t\t\tcanvas.tabIndex = 0;
\t\t\tconst focusCanvas = () => {
\t\t\t\ttry {
\t\t\t\t\tcanvas.focus({ preventScroll: true });
\t\t\t\t} catch (_) {
\t\t\t\t\tcanvas.focus();
\t\t\t\t}
\t\t\t};
\t\t\tcanvas.addEventListener('pointerdown', focusCanvas, { capture: true });
\t\t\tcanvas.addEventListener('mousedown', focusCanvas, { capture: true });
\t\t\tcanvas.addEventListener('touchstart', focusCanvas, { capture: true, passive: true });
\t\t\twindow.addEventListener('focus', focusCanvas);
\t\t}

\t\tconst updateDownloadProgress = function (current, total) {
\t\t\tif (current > 0 && total > 0) {
\t\t\t\tstatusProgress.value = current;
\t\t\t\tstatusProgress.max = total;
\t\t\t} else {
\t\t\t\tstatusProgress.removeAttribute('value');
\t\t\t\tstatusProgress.removeAttribute('max');
\t\t\t}
\t\t};

\t\tasync function loadChunkedMainPack() {
\t\t\tconst manifestResponse = await fetch('index.pck.parts.json', { cache: 'no-store' });
\t\t\tif (!manifestResponse.ok) {
\t\t\t\tthrow new Error(`Failed to load PCK manifest: HTTP ${manifestResponse.status}`);
\t\t\t}
\t\t\tconst manifest = await manifestResponse.json();
\t\t\tif (!manifest || manifest.contentEncoding !== 'identity' || !Array.isArray(manifest.parts) || manifest.parts.length === 0) {
\t\t\t\tthrow new Error('Invalid raw PCK chunk manifest.');
\t\t\t}

\t\t\tconst total = Number(manifest.originalSize || manifest.encodedSize || 0);
\t\t\tif (!Number.isSafeInteger(total) || total <= 0) {
\t\t\t\tthrow new Error('Invalid PCK size in manifest.');
\t\t\t}

\t\t\tconst merged = new Uint8Array(total);
\t\t\tlet offset = 0;
\t\t\tfor (const part of manifest.parts) {
\t\t\t\tif (!/^[A-Za-z0-9._-]+$/.test(String(part))) {
\t\t\t\t\tthrow new Error(`Invalid PCK chunk name: ${part}`);
\t\t\t\t}
\t\t\t\tconst response = await fetch(String(part), { cache: 'no-store' });
\t\t\t\tif (!response.ok) {
\t\t\t\t\tthrow new Error(`Failed to load PCK chunk ${part}: HTTP ${response.status}`);
\t\t\t\t}
\t\t\t\tconst bytes = new Uint8Array(await response.arrayBuffer());
\t\t\t\tif (offset + bytes.byteLength > merged.byteLength) {
\t\t\t\t\tthrow new Error(`PCK chunk overflow at ${part}`);
\t\t\t\t}
\t\t\t\tmerged.set(bytes, offset);
\t\t\t\toffset += bytes.byteLength;
\t\t\t\tupdateDownloadProgress(offset, total);
\t\t\t}

\t\t\tif (offset !== total) {
\t\t\t\tthrow new Error(`PCK size mismatch: expected ${total}, received ${offset}`);
\t\t\t}
\t\t\tif (merged[0] !== 0x47 || merged[1] !== 0x44 || merged[2] !== 0x50 || merged[3] !== 0x43) {
\t\t\t\tthrow new Error(`Invalid PCK header: ${Array.from(merged.slice(0, 4)).map((v) => v.toString(16).padStart(2, '0')).join(' ')}`);
\t\t\t}
\t\t\treturn merged.buffer;
\t\t}

\t\tPromise.all([
\t\t\tengine.init('index'),
\t\t\tloadChunkedMainPack().then((buffer) => engine.preloadFile(buffer, 'index.pck')),
\t\t]).then(() => engine.start({
\t\t\targs: ['--main-pack', 'index.pck'],
\t\t\tcanvas: canvas,
\t\t\tcanvasResizePolicy: 2,
\t\t\t'onProgress': updateDownloadProgress,
\t\t})).then(() => {
\t\t\tsetStatusMode('hidden');
\t\t\tif (canvas) {
\t\t\t\trequestAnimationFrame(() => {
\t\t\t\t\ttry {
\t\t\t\t\t\tcanvas.focus({ preventScroll: true });
\t\t\t\t\t} catch (_) {
\t\t\t\t\t\tcanvas.focus();
\t\t\t\t\t}
\t\t\t\t});
\t\t\t}
\t\t}, displayFailureNotice);'''

patched, count = pattern.subn(replacement, html, count=1)
if count != 1:
    raise SystemExit(f"Could not patch Godot startGame block; matches={count}")
html_path.write_text(patched, encoding="utf-8")
PY

python3 - "$OUT_DIR/index.html" <<'PY'
from pathlib import Path
import sys

html = Path(sys.argv[1]).read_text(encoding="utf-8")
for forbidden in (
    "syncCanvasOneToOne",
    "canvas.width =",
    "canvas.height =",
    "canvasResizePolicy: 0",
):
    if forbidden in html:
        raise SystemExit(f"Unsafe manual canvas sizing found: {forbidden}")
if "canvasResizePolicy: 2" not in html:
    raise SystemExit("Godot Adaptive canvas policy is not active")
PY

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
