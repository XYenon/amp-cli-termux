#!/usr/bin/env bash
# Amp CLI - Termux Standalone Installer
set -euo pipefail

# EDIT THIS: Set this to your GitHub username and repository name
REPO="${AMP_REPO:-XYenon/amp-cli-termux}"
RAW_BASE="https://raw.githubusercontent.com/$REPO/main"

AMP_HOME="${AMP_HOME:-$HOME/.amp}"
BIN_DIR="$AMP_HOME/bin"
BUN_DIR="$HOME/.bun"
LOCAL_BIN="$HOME/.local/bin"

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
for cmd in curl uname mktemp chmod mkdir rm sha256sum; do
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
mkdir -p "$BUN_DIR/bin"
mkdir -p "$BUN_DIR/lib"
mkdir -p "$BUN_DIR/tmp"
mkdir -p "$LOCAL_BIN"

# ── Download bun-termux wrapper & shim ────────────────────────────────────────
echo "[*] Downloading bun-termux wrapper & shim..."
curl -fsSL "https://github.com/$REPO/releases/download/$latest_version/bun-termux-aarch64" -o "$BUN_DIR/bin/bun"
curl -fsSL "https://github.com/$REPO/releases/download/$latest_version/bun-shim-aarch64.so" -o "$BUN_DIR/lib/bun-shim.so"
chmod +x "$BUN_DIR/bin/bun"

# ── Fetch latest version ──────────────────────────────────────────────────────
echo "[*] Fetching latest patched version..."
latest_version=$(curl -fsSL "$RAW_BASE/cli/cli-version.txt" | tr -d '\r\n[:space:]')
echo "[+] Latest patched version is: $latest_version"

# ── Download Amp binary ───────────────────────────────────────────────────────
temp_gz=$(mktemp "$BIN_DIR/tmp.XXXXXX.gz")
temp_bin=$(mktemp "$BIN_DIR/tmp.XXXXXX")

echo "[*] Downloading patched Amp binary..."
curl -fsSL "https://github.com/$REPO/releases/download/$latest_version/amp-linux-arm64.gz" -o "$temp_gz"
gzip -dc "$temp_gz" > "$temp_bin"
rm -f "$temp_gz"

# ── Verify checksum ───────────────────────────────────────────────────────────
echo "[*] Verifying checksum..."
expected_checksum=$(curl -fsSL "https://github.com/$REPO/releases/download/$latest_version/linux-arm64-amp.sha256" | tr -d '\r\n[:space:]')
actual_checksum=$(sha256sum "$temp_bin" | cut -d' ' -f1)

if [[ "$actual_checksum" != "$expected_checksum" ]]; then
  rm -f "$temp_bin"
  echo "[ERR] Checksum verification failed!" >&2
  echo "Expected: $expected_checksum" >&2
  echo "Actual:   $actual_checksum" >&2
  exit 1
fi
echo "[+] Checksum verified."

# Atomic move
mv "$temp_bin" "$BIN_DIR/amp"
chmod +x "$BIN_DIR/amp"

# ── Create the native wrapper script ──────────────────────────────────────────
echo "[*] Creating native wrapper at $LOCAL_BIN/amp..."
rm -f "$LOCAL_BIN/amp"

# We export AMP_STORAGE_BASE pointing to our GitHub raw URL so that built-in updates
# check our repository instead of the official static.ampcode.com!
cat << EOF > "$LOCAL_BIN/amp"
#!/data/data/com.termux/files/usr/bin/bash
export BUN_INSTALL="\$HOME/.bun"
export AMP_STORAGE_BASE="$RAW_BASE"
exec "$BIN_DIR/amp" "\$@"
EOF
chmod +x "$LOCAL_BIN/amp"

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
echo "Please restart your terminal or run: source ~/.bashrc"
echo "To run it, use: amp"
echo "========================================="
