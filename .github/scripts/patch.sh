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
python3 replace_runtime.py download/amp-linux-arm64 "cli/${LATEST_VERSION}/amp" --wrapper bun

# 3. Copy separate runtime files into the release directory
cp bun "cli/${LATEST_VERSION}/bun"
cp bun-shim.so "cli/${LATEST_VERSION}/bun-shim.so"

# 4. Calculate SHA256 checksums
(cd "cli/${LATEST_VERSION}" && sha256sum amp bun bun-shim.so > sha256sums.txt)

# 5. Clean up temporary files
rm -rf download

# 6. Update global version file
mkdir -p cli
echo "${LATEST_VERSION}" > cli/cli-version.txt

