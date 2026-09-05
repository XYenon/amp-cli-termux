#!/usr/bin/env bash
# Amp CLI - Termux Standalone Installer
set -euo pipefail

# EDIT THIS: Set this to your GitHub username and repository name
REPO="${AMP_REPO:-XYenon/amp-cli-termux}"
RAW_BASE="https://raw.githubusercontent.com/$REPO/main"

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
for cmd in curl uname mktemp chmod mkdir rmdir rm mv grep cut tr sha256sum unzip tar; do
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
echo "[*] Installing Amp private glibc Bun..."
temp_zip=$(mktemp "$AMP_RUNTIME_DIR/tmp.XXXXXX.zip")
curl -fsSL "https://github.com/oven-sh/bun/releases/latest/download/bun-linux-aarch64.zip" -o "$temp_zip"
temp_buno=$(mktemp "$AMP_RUNTIME_DIR/bin/tmp.buno.XXXXXX")
unzip -p "$temp_zip" "bun-linux-aarch64/bun" > "$temp_buno"
rm -f "$temp_zip"
chmod +x "$temp_buno"
mv "$temp_buno" "$AMP_RUNTIME_DIR/bin/buno"

# ── Fetch latest version ──────────────────────────────────────────────────────
echo "[*] Fetching latest patched version..."
latest_version=$(curl -fsSL "$RAW_BASE/cli/cli-version.txt" | tr -d '\r\n[:space:]')
echo "[+] Latest patched version is: $latest_version"

# ── Download release archive ──────────────────────────────────────────────────
echo "[*] Downloading patched release archive..."
temp_tarball=$(mktemp "$AMP_HOME/tmp.XXXXXX.tar.gz")

curl -fsSL "https://github.com/$REPO/releases/download/$latest_version/amp-termux-aarch64.tar.gz" -o "$temp_tarball"

# ── Verify checksum ───────────────────────────────────────────────────────────
echo "[*] Verifying checksum..."
expected_checksum=$(curl -fsSL "https://github.com/$REPO/releases/download/$latest_version/amp-termux-aarch64.tar.gz.sha256" | tr -d '\r\n[:space:]')
actual_checksum=$(sha256sum "$temp_tarball" | cut -d' ' -f1)

if [[ "$actual_checksum" != "$expected_checksum" ]]; then
  rm -f "$temp_tarball"
  echo "[ERR] Checksum verification failed!" >&2
  echo "Expected: $expected_checksum" >&2
  echo "Actual:   $actual_checksum" >&2
  exit 1
fi
echo "[+] Checksum verified."

# ── Extract files ─────────────────────────────────────────────────────────────
echo "[*] Extracting files..."
extract_dir=$(mktemp -d "$AMP_HOME/tmp_extract.XXXXXX")
tar -xzf "$temp_tarball" -C "$extract_dir"
rm -f "$temp_tarball"

# Move files to their respective locations
chmod +x "$extract_dir/bun"
mv "$extract_dir/bun" "$AMP_RUNTIME_DIR/bin/bun"
mv "$extract_dir/bun-shim.so" "$AMP_RUNTIME_DIR/lib/bun-shim.so"

chmod +x "$extract_dir/amp"
mv "$extract_dir/amp" "$BIN_DIR/amp"

# Clean extract directory
rm -rf "$extract_dir"

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
