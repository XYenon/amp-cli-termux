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
for cmd in curl uname mktemp chmod mkdir rm sha256sum unzip tar; do
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

# ── Setup official glibc bun as buno ──────────────────────────────────────────
echo "[*] Setting up official glibc bun..."
if [ -f "$BUN_DIR/bin/buno" ]; then
  echo "[+] buno already exists."
elif [ -f "$BUN_DIR/bin/bun" ] && ! grep -q "bun-termux" "$BUN_DIR/bin/bun" 2>/dev/null; then
  echo "[*] Renaming existing bun to buno..."
  mv "$BUN_DIR/bin/bun" "$BUN_DIR/bin/buno"
else
  echo "[*] Downloading official glibc bun..."
  temp_zip=$(mktemp "$BUN_DIR/tmp.XXXXXX.zip")
  curl -fsSL "https://github.com/oven-sh/bun/releases/latest/download/bun-linux-aarch64.zip" -o "$temp_zip"
  temp_buno=$(mktemp "$BUN_DIR/bin/tmp.buno.XXXXXX")
  unzip -p "$temp_zip" "bun-linux-aarch64/bun" > "$temp_buno"
  rm -f "$temp_zip"
  chmod +x "$temp_buno"
  mv "$temp_buno" "$BUN_DIR/bin/buno"
fi

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
mv "$extract_dir/bun" "$BUN_DIR/bin/bun"
mv "$extract_dir/bun-shim.so" "$BUN_DIR/lib/bun-shim.so"

chmod +x "$extract_dir/amp"
mv "$extract_dir/amp" "$BIN_DIR/amp"

# Clean extract directory
rm -rf "$extract_dir"

# ── Create the native wrapper script ──────────────────────────────────────────
echo "[*] Creating native wrapper at $LOCAL_BIN/amp..."
temp_wrapper=$(mktemp "$LOCAL_BIN/tmp.amp.XXXXXX")

cat << 'EOF' > "$temp_wrapper"
#!/data/data/com.termux/files/usr/bin/bash
export BUN_INSTALL="$HOME/.bun"
export AMP_SKIP_UPDATE_CHECK="1"
exec "/data/data/com.termux/files/home/.amp/bin/amp" "$@"
EOF
chmod +x "$temp_wrapper"
mv "$temp_wrapper" "$LOCAL_BIN/amp"

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
