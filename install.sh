#!/usr/bin/env bash
# Amp CLI - Termux Standalone Installer
set -euo pipefail

# EDIT THIS: Set this to your GitHub username and repository name
REPO="${AMP_REPO:-XYenon/amp-cli-termux}"
RAW_BASE="${AMP_RAW_BASE:-https://raw.githubusercontent.com/$REPO/main}"

AMP_HOME="${AMP_HOME:-$HOME/.amp}"
BIN_DIR="$AMP_HOME/bin"
AMP_RUNTIME_DIR="$AMP_HOME/runtime"
LOCAL_BIN="${LOCAL_BIN:-$HOME/.local/bin}"
LEGACY_BUN_DIR="$HOME/.bun"

if [[ -z "${TERMUX_VERSION:-}" || -z "${PREFIX:-}" ]]; then
  echo "✗ This installer is only for native Termux." >&2
  exit 1
fi

for cmd in curl uname mktemp chmod mkdir rmdir rm mv grep cut tr sha256sum awk sed unzip; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "✗ Required command '$cmd' not found. Please install it first." >&2
    exit 1
  fi
done

# Check architecture
platform="$(uname -s) $(uname -m)"
if [[ "$platform" != "Linux aarch64" && "$platform" != "Linux arm64" ]]; then
  echo "✗ Standalone Termux installer is only supported on aarch64 (ARM64) devices." >&2
  exit 1
fi

# Create directories
mkdir -p "$BIN_DIR"
mkdir -p "$AMP_RUNTIME_DIR/bin"
mkdir -p "$AMP_RUNTIME_DIR/lib"
mkdir -p "$AMP_RUNTIME_DIR/tmp"
mkdir -p "$LOCAL_BIN"

# ── Fetch latest version and checksums ────────────────────────────────────────
latest_version=$(curl -fsSL "$RAW_BASE/cli/cli-version.txt" 2>/dev/null | tr -d '\r\n[:space:]' || true)
if [[ -z "$latest_version" ]]; then
  echo "✗ Failed to fetch latest version info." >&2
  exit 1
fi

RELEASE_BASE="${AMP_RELEASE_BASE:-https://github.com/$REPO/releases/download/$latest_version}"
temp_sums=$(mktemp "$AMP_HOME/tmp.sums.XXXXXX")
trap 'rm -f "$temp_sums"' EXIT INT TERM

if ! curl -fsSL "$RELEASE_BASE/sha256sums.txt" -o "$temp_sums"; then
  echo "✗ Failed to download checksums from $RELEASE_BASE" >&2
  exit 1
fi

get_expected_hash() {
  local target="$1"
  awk -v f="$target" '$2 == f || $2 == ("*" f) {print $1; exit}' "$temp_sums"
}

# Verify checksums file contains all required assets
for f in "bun" "bun-shim.so" "amp"; do
  if [[ -z "$(get_expected_hash "$f")" ]]; then
    echo "✗ Checksum for $f not found in sha256sums.txt!" >&2
    exit 1
  fi
done

# ── Check Amp private glibc Bun compatibility runtime ─────────────────────────
bun_latest_url="${AMP_BUN_LATEST_URL:-https://github.com/oven-sh/bun/releases/latest}"
bun_download_base="${AMP_BUN_DOWNLOAD_BASE:-https://github.com/oven-sh/bun/releases/download}"

latest_bun_tag=$( (curl -fsSLI -o /dev/null -w "%{url_effective}" "$bun_latest_url" 2>/dev/null || true) | tr -d '\r\n[:space:]' | sed 's#.*/##' )

current_bun_tag=""
if [[ -f "$AMP_RUNTIME_DIR/bun-version.txt" ]]; then
  current_bun_tag=$(cat "$AMP_RUNTIME_DIR/bun-version.txt" 2>/dev/null | tr -d '\r\n[:space:]')
elif [[ -x "$AMP_RUNTIME_DIR/bin/buno" && -f "$PREFIX/glibc/lib/ld-linux-aarch64.so.1" ]]; then
  detected_ver=$("$PREFIX/glibc/lib/ld-linux-aarch64.so.1" "$AMP_RUNTIME_DIR/bin/buno" --version 2>/dev/null || true)
  if [[ -n "$detected_ver" ]]; then
    current_bun_tag="bun-v$detected_ver"
    echo "$current_bun_tag" > "$AMP_RUNTIME_DIR/bun-version.txt"
  fi
fi

need_bun=0
if [[ ! -x "$AMP_RUNTIME_DIR/bin/buno" ]]; then
  need_bun=1
elif [[ -n "$latest_bun_tag" && "$current_bun_tag" != "$latest_bun_tag" ]]; then
  need_bun=1
fi

if [[ -x "$AMP_RUNTIME_DIR/bin/buno" && -z "$latest_bun_tag" ]]; then
  echo "⚠ Unable to check remote Bun version; using existing Bun installation." >&2
fi

# ── Check release files ───────────────────────────────────────────────────────
file_needs_download() {
  local filename="$1"
  local dest="$2"
  local expected_hash
  expected_hash=$(get_expected_hash "$filename")

  if [[ ! -f "$dest" ]]; then
    return 0
  fi

  local current_hash
  current_hash=$(sha256sum "$dest" | cut -d' ' -f1)
  [[ "$current_hash" != "$expected_hash" ]]
}

need_bun_wrapper=0
need_shim=0
need_amp=0

if file_needs_download "bun" "$AMP_RUNTIME_DIR/bin/bun"; then
  need_bun_wrapper=1
fi
if file_needs_download "bun-shim.so" "$AMP_RUNTIME_DIR/lib/bun-shim.so"; then
  need_shim=1
fi
if file_needs_download "amp" "$BIN_DIR/amp"; then
  need_amp=1
fi

need_wrapper=0
if [[ ! -x "$LOCAL_BIN/amp" ]]; then
  need_wrapper=1
fi

# ── Helper functions for system maintenance ───────────────────────────────────
create_wrapper() {
  local temp_wrapper
  temp_wrapper=$(mktemp "$LOCAL_BIN/tmp.amp.XXXXXX")
  {
    echo "#!$PREFIX/bin/bash"
    printf 'export BUN_INSTALL=%q\n' "$AMP_RUNTIME_DIR"
    printf 'export BUN_BINARY_PATH=%q\n' "$AMP_RUNTIME_DIR/bin/buno"
    echo 'export AMP_SKIP_UPDATE_CHECK="1"'
    printf 'exec %q "$@"\n' "$BIN_DIR/amp"
  } > "$temp_wrapper"
  chmod +x "$temp_wrapper"
  mv "$temp_wrapper" "$LOCAL_BIN/amp"
}

clean_legacy() {
  rm -f "$LEGACY_BUN_DIR/bin/buno"
  rm -f "$LEGACY_BUN_DIR/lib/bun-shim.so"
  rm -f "$LEGACY_BUN_DIR/tmp/install.sh"
  rm -rf "$LEGACY_BUN_DIR/tmp/fake-root"

  if [[ -f "$LEGACY_BUN_DIR/bin/bun" ]] && grep -aq 'bun-termux:' "$LEGACY_BUN_DIR/bin/bun"; then
    rm -f "$LEGACY_BUN_DIR/bin/bun"
  fi

  rmdir "$LEGACY_BUN_DIR/lib" "$LEGACY_BUN_DIR/tmp" "$LEGACY_BUN_DIR/bin" "$LEGACY_BUN_DIR" 2>/dev/null || true
}

setup_dns() {
  mkdir -p "$PREFIX/glibc/etc"
  mkdir -p "$PREFIX/etc"
  for rc in "$PREFIX/glibc/etc/resolv.conf" "$PREFIX/etc/resolv.conf"; do
    if [ ! -f "$rc" ] || ! grep -q "nameserver" "$rc" 2>/dev/null; then
      echo -e "nameserver 223.5.5.5\nnameserver 1.1.1.1\nnameserver 8.8.8.8" > "$rc"
    fi
  done
}

# ── If everything is up to date, finish silently and report ───────────────────
if [[ "$need_bun" -eq 0 && "$need_bun_wrapper" -eq 0 && "$need_shim" -eq 0 && "$need_amp" -eq 0 && "$need_wrapper" -eq 0 ]]; then
  create_wrapper
  clean_legacy
  setup_dns
  echo "✓ Amp CLI is already up to date ($latest_version)."
  exit 0
fi

# ── Perform installation / update ─────────────────────────────────────────────
is_update=0
if [[ -x "$BIN_DIR/amp" && -x "$LOCAL_BIN/amp" ]]; then
  is_update=1
  echo "→ Updating Amp CLI ($latest_version)..."
else
  echo "→ Installing Amp CLI ($latest_version)..."
fi

if [[ "$need_bun" -eq 1 ]]; then
  echo "→ Downloading Bun runtime (${latest_bun_tag:-latest})..."
  bun_download_url="$bun_download_base/bun-linux-aarch64.zip"
  if [[ -n "$latest_bun_tag" ]]; then
    bun_download_url="$bun_download_base/${latest_bun_tag}/bun-linux-aarch64.zip"
  fi

  temp_zip=$(mktemp "$AMP_RUNTIME_DIR/tmp.XXXXXX.zip")
  if ! curl -fsSL "$bun_download_url" -o "$temp_zip"; then
    rm -f "$temp_zip"
    echo "✗ Failed to download Bun runtime from $bun_download_url" >&2
    exit 1
  fi

  if [[ -n "$latest_bun_tag" ]]; then
    expected_bun_sha=$(curl -fsSL "$bun_download_base/${latest_bun_tag}/SHASUMS256.txt" 2>/dev/null | awk '$2 == "bun-linux-aarch64.zip" {print $1; exit}')
    if [[ -n "$expected_bun_sha" ]]; then
      actual_bun_sha=$(sha256sum "$temp_zip" | cut -d' ' -f1)
      if [[ "$actual_bun_sha" != "$expected_bun_sha" ]]; then
        rm -f "$temp_zip"
        echo "✗ Bun archive checksum verification failed!" >&2
        echo "Expected: $expected_bun_sha" >&2
        echo "Actual:   $actual_bun_sha" >&2
        exit 1
      fi
    fi
  fi

  temp_buno=$(mktemp "$AMP_RUNTIME_DIR/bin/tmp.buno.XXXXXX")
  if ! unzip -p "$temp_zip" "bun-linux-aarch64/bun" > "$temp_buno"; then
    rm -f "$temp_zip" "$temp_buno"
    echo "✗ Failed to extract Bun binary!" >&2
    exit 1
  fi
  rm -f "$temp_zip"
  chmod +x "$temp_buno"
  mv "$temp_buno" "$AMP_RUNTIME_DIR/bin/buno"
  if [[ -n "$latest_bun_tag" ]]; then
    echo "$latest_bun_tag" > "$AMP_RUNTIME_DIR/bun-version.txt"
  fi
fi

download_file() {
  local filename="$1"
  local dest="$2"
  local is_exec="${3:-0}"
  local expected_hash
  expected_hash=$(get_expected_hash "$filename")

  echo "→ Downloading $filename..."
  local dir
  dir="$(dirname "$dest")"
  mkdir -p "$dir"
  local temp_file
  temp_file=$(mktemp "$dir/tmp.$filename.XXXXXX")

  if ! curl -fsSL "$RELEASE_BASE/$filename" -o "$temp_file"; then
    rm -f "$temp_file"
    echo "✗ Failed to download $filename!" >&2
    exit 1
  fi

  local actual_hash
  actual_hash=$(sha256sum "$temp_file" | cut -d' ' -f1)
  if [[ "$actual_hash" != "$expected_hash" ]]; then
    rm -f "$temp_file"
    echo "✗ Checksum verification failed for $filename!" >&2
    echo "Expected: $expected_hash" >&2
    echo "Actual:   $actual_hash" >&2
    exit 1
  fi

  if [[ "$is_exec" == "1" ]]; then
    chmod +x "$temp_file"
  fi
  mv "$temp_file" "$dest"
}

if [[ "$need_bun_wrapper" -eq 1 ]]; then
  download_file "bun" "$AMP_RUNTIME_DIR/bin/bun" 1
fi
if [[ "$need_shim" -eq 1 ]]; then
  download_file "bun-shim.so" "$AMP_RUNTIME_DIR/lib/bun-shim.so" 0
fi
if [[ "$need_amp" -eq 1 ]]; then
  download_file "amp" "$BIN_DIR/amp" 1
fi

create_wrapper
clean_legacy
setup_dns

if [[ "$is_update" -eq 1 ]]; then
  echo "✓ Amp CLI updated to $latest_version."
else
  echo "✓ Amp CLI ($latest_version) installed successfully."
  case ":$PATH:" in
    *":$LOCAL_BIN:"*)
      echo "To run it, use: amp"
      ;;
    *)
      echo ""
      echo "Add $LOCAL_BIN to your PATH to run 'amp':"
      echo "  echo 'export PATH=\"$LOCAL_BIN:\$PATH\"' >> ~/.bashrc && source ~/.bashrc"
      ;;
  esac
fi
