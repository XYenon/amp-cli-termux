#!/usr/bin/env bash
set -e

if [ -z "$LATEST_VERSION" ]; then
  echo "Error: LATEST_VERSION environment variable is not set."
  exit 1
fi

# 1. Download official amp-linux-arm64
mkdir -p download
curl -fsSL "https://static.ampcode.com/cli/${LATEST_VERSION}/amp-linux-arm64.gz" -o download/amp-linux-arm64.gz
gunzip download/amp-linux-arm64.gz

# 2. Patch using replace_runtime.py and the compiled wrapper
mkdir -p "cli/${LATEST_VERSION}"
python3 replace_runtime.py download/amp-linux-arm64 "cli/${LATEST_VERSION}/amp-linux-arm64" --wrapper bun

# 3. Package the files into a tarball
mkdir -p pack
cp "cli/${LATEST_VERSION}/amp-linux-arm64" pack/amp
cp bun pack/
cp bun-shim.so pack/

tar -czf "cli/${LATEST_VERSION}/amp-termux-aarch64.tar.gz" -C pack amp bun bun-shim.so

# 4. Calculate SHA256 of the tgz archive
sha256sum "cli/${LATEST_VERSION}/amp-termux-aarch64.tar.gz" | cut -d' ' -f1 > "cli/${LATEST_VERSION}/amp-termux-aarch64.tar.gz.sha256"

# 5. Clean up temporary files and pack directory
rm -rf pack download "cli/${LATEST_VERSION}/amp-linux-arm64"

# 6. Update global version file
mkdir -p cli
echo "${LATEST_VERSION}" > cli/cli-version.txt

