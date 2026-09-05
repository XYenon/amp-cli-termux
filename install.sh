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
  echo "[ERR] This installer is only for native Termux." >&2
  exit 1
fi

echo "========================================="
echo "  Amp CLI - Termux Standalone Installer  "
echo "========================================="
echo "Repository: $REPO"
echo "Install directory: $BIN_DIR"
echo "========================================="

# ── Prerequisites ─────────────────────────────────────────────────────────────
echo "[*] Checking prerequisites..."
for cmd in curl uname mktemp chmod mkdir rmdir rm mv grep cut tr sha256sum awk sed unzip; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[ERR] Required command '$cmd' not found. Please install it first." >&2
    exit 1
  fi
done

# Check architecture
platform="$(uname -s) $(uname -m)"
if [[ "$platform" != "Linux aarch64" && "$platform" != "Linux arm64" ]]; then
  echo "[ERR] Standalone Termux installer is only supported on aarch64 (ARM64) devices." >&2
  exit 1
fi

# Create directories
mkdir -p "$BIN_DIR"
mkdir -p "$AMP_RUNTIME_DIR/bin"
mkdir -p "$AMP_RUNTIME_DIR/lib"
mkdir -p "$AMP_RUNTIME_DIR/tmp"
mkdir -p "$LOCAL_BIN"

# ── Setup Amp's private glibc Bun compatibility runtime ───────────────────────
# Amp still embeds a Linux/glibc keyring native addon, so it cannot yet run on
# Android Bun directly. Keep the compatibility runtime private to Amp instead
# of replacing or otherwise modifying the user's Bun installation.
echo "[*] Checking Amp private glibc Bun version..."
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

if [[ -x "$AMP_RUNTIME_DIR/bin/buno" && -n "$latest_bun_tag" && "$current_bun_tag" == "$latest_bun_tag" ]]; then
  echo "[+] Amp private glibc Bun ($current_bun_tag) is already up to date, skipping download."
elif [[ -x "$AMP_RUNTIME_DIR/bin/buno" && -z "$latest_bun_tag" ]]; then
  echo "[!] Unable to check remote Bun version; using existing Bun installation."
else
  echo "[*] Installing/updating Amp private glibc Bun (${latest_bun_tag:-latest})..."
  bun_download_url="$bun_download_base/bun-linux-aarch64.zip"
  if [[ -n "$latest_bun_tag" ]]; then
    bun_download_url="$bun_download_base/${latest_bun_tag}/bun-linux-aarch64.zip"
  fi

  temp_zip=$(mktemp "$AMP_RUNTIME_DIR/tmp.XXXXXX.zip")
  curl -fsSL "$bun_download_url" -o "$temp_zip"

  # Optional checksum verification if SHASUMS256.txt is available
  if [[ -n "$latest_bun_tag" ]]; then
    expected_bun_sha=$(curl -fsSL "$bun_download_base/${latest_bun_tag}/SHASUMS256.txt" 2>/dev/null | awk '$2 == "bun-linux-aarch64.zip" {print $1; exit}')
    if [[ -n "$expected_bun_sha" ]]; then
      actual_bun_sha=$(sha256sum "$temp_zip" | cut -d' ' -f1)
      if [[ "$actual_bun_sha" != "$expected_bun_sha" ]]; then
        rm -f "$temp_zip"
        echo "[ERR] Bun archive checksum verification failed!" >&2
        echo "Expected: $expected_bun_sha" >&2
        echo "Actual:   $actual_bun_sha" >&2
        exit 1
      fi
    fi
  fi

  temp_buno=$(mktemp "$AMP_RUNTIME_DIR/bin/tmp.buno.XXXXXX")
  unzip -p "$temp_zip" "bun-linux-aarch64/bun" > "$temp_buno"
  rm -f "$temp_zip"
  chmod +x "$temp_buno"
  mv "$temp_buno" "$AMP_RUNTIME_DIR/bin/buno"
  if [[ -n "$latest_bun_tag" ]]; then
    echo "$latest_bun_tag" > "$AMP_RUNTIME_DIR/bun-version.txt"
  fi
  echo "[+] Amp private glibc Bun installed successfully (${latest_bun_tag:-latest})."
fi

# ── Fetch latest version ──────────────────────────────────────────────────────
echo "[*] Fetching latest patched version..."
latest_version=$(curl -fsSL "$RAW_BASE/cli/cli-version.txt" | tr -d '\r\n[:space:]')
echo "[+] Latest patched version is: $latest_version"

# ── Download release files with SHA256 check ──────────────────────────────────
RELEASE_BASE="${AMP_RELEASE_BASE:-https://github.com/$REPO/releases/download/$latest_version}"
temp_sums=$(mktemp "$AMP_HOME/tmp.sums.XXXXXX")

echo "[*] Fetching release checksums..."
if ! curl -fsSL "$RELEASE_BASE/sha256sums.txt" -o "$temp_sums"; then
  rm -f "$temp_sums"
  echo "[ERR] Failed to download sha256sums.txt from $RELEASE_BASE" >&2
  exit 1
fi

echo "[*] Comparing local files before downloading..."

get_expected_hash() {
  local target="$1"
  awk -v f="$target" '$2 == f || $2 == ("*" f) {print $1; exit}' "$temp_sums"
}

install_file() {
  local filename="$1"
  local dest="$2"
  local is_exec="${3:-0}"
  local expected_hash
  expected_hash=$(get_expected_hash "$filename")

  if [[ -z "$expected_hash" ]]; then
    echo "[ERR] Checksum for $filename not found in sha256sums.txt!" >&2
    return 1
  fi

  if [[ -f "$dest" ]]; then
    local current_hash
    current_hash=$(sha256sum "$dest" | cut -d' ' -f1)
    if [[ "$current_hash" == "$expected_hash" ]]; then
      echo "[+] $filename is already up to date, skipping download."
      return 0
    fi
  fi

  echo "[*] Downloading $filename..."
  local dir
  dir="$(dirname "$dest")"
  mkdir -p "$dir"
  local temp_file
  temp_file=$(mktemp "$dir/tmp.$filename.XXXXXX")

  if ! curl -fsSL "$RELEASE_BASE/$filename" -o "$temp_file"; then
    rm -f "$temp_file"
    echo "[ERR] Failed to download $filename!" >&2
    return 1
  fi

  local actual_hash
  actual_hash=$(sha256sum "$temp_file" | cut -d' ' -f1)
  if [[ "$actual_hash" != "$expected_hash" ]]; then
    rm -f "$temp_file"
    echo "[ERR] Checksum verification failed for $filename!" >&2
    echo "Expected: $expected_hash" >&2
    echo "Actual:   $actual_hash" >&2
    return 1
  fi

  if [[ "$is_exec" == "1" ]]; then
    chmod +x "$temp_file"
  fi
  mv "$temp_file" "$dest"
  echo "[+] $filename installed successfully."
}

install_file "bun" "$AMP_RUNTIME_DIR/bin/bun" 1
install_file "bun-shim.so" "$AMP_RUNTIME_DIR/lib/bun-shim.so" 0
install_file "amp" "$BIN_DIR/amp" 1

rm -f "$temp_sums"

# ── Create the native wrapper script ──────────────────────────────────────────
echo "[*] Creating native wrapper at $LOCAL_BIN/amp..."
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

# Remove files left by releases that installed Amp's compatibility runtime in
# ~/.bun. Preserve an official/user-managed Bun unless it is our old wrapper.
echo "[*] Cleaning legacy Amp runtime files from $LEGACY_BUN_DIR..."
rm -f "$LEGACY_BUN_DIR/bin/buno"
rm -f "$LEGACY_BUN_DIR/lib/bun-shim.so"
rm -f "$LEGACY_BUN_DIR/tmp/install.sh"
rm -rf "$LEGACY_BUN_DIR/tmp/fake-root"

if [[ -f "$LEGACY_BUN_DIR/bin/bun" ]] && grep -aq 'bun-termux:' "$LEGACY_BUN_DIR/bin/bun"; then
  echo "[*] Removing legacy bun-termux wrapper from $LEGACY_BUN_DIR/bin/bun..."
  rm -f "$LEGACY_BUN_DIR/bin/bun"
fi

# Remove directories only when the user has nothing else stored in them.
rmdir "$LEGACY_BUN_DIR/lib" "$LEGACY_BUN_DIR/tmp" "$LEGACY_BUN_DIR/bin" "$LEGACY_BUN_DIR" 2>/dev/null || true

# ── Ensure DNS config works in glibc ──────────────────────────────────────────
echo "[*] Setting up DNS configuration for glibc..."
mkdir -p "$PREFIX/glibc/etc"
mkdir -p "$PREFIX/etc"
for rc in "$PREFIX/glibc/etc/resolv.conf" "$PREFIX/etc/resolv.conf"; do
  if [ ! -f "$rc" ] || ! grep -q "nameserver" "$rc" 2>/dev/null; then
    echo -e "nameserver 223.5.5.5\nnameserver 1.1.1.1\nnameserver 8.8.8.8" > "$rc"
  fi
done


echo "========================================="
echo "[+] Success! Amp CLI has been installed natively."
echo "[+] Amp compatibility runtime is private at: $AMP_RUNTIME_DIR"
echo "Please restart your terminal or run: source ~/.bashrc"
echo "To run it, use: amp"
echo "========================================="
