#!/usr/bin/env bash
set -e

if [ -z "$LATEST_VERSION" ]; then
  echo "Error: LATEST_VERSION environment variable is not set."
  exit 1
fi

if [ -z "$VERSION_COMMIT" ]; then
  echo "Error: VERSION_COMMIT environment variable is not set."
  exit 1
fi

# Create GitHub Release or upload assets (use --clobber to overwrite if exists).
# --target pins the tag to the version-file commit instead of the previous commit.
if gh release view "$LATEST_VERSION" >/dev/null 2>&1; then
  echo "Release already exists. Uploading assets with --clobber..."
  gh release upload "$LATEST_VERSION" \
    "cli/${LATEST_VERSION}/amp-termux-aarch64.tar.gz" \
    "cli/${LATEST_VERSION}/amp-termux-aarch64.tar.gz.sha256" \
    --clobber
else
  echo "Creating new release..."

  cat <<EOF > release_notes.md
Automated patched release of Amp CLI $LATEST_VERSION for native Termux (ARM64/aarch64).

## Assets

- \`amp-termux-aarch64.tar.gz\` - A complete archive containing:
  - \`amp\` - Patched Amp CLI binary
  - \`bun\` - \`bun-termux\` wrapper binary
  - \`bun-shim.so\` - \`LD_PRELOAD\` shim for path translation and system call intercept
- \`amp-termux-aarch64.tar.gz.sha256\` - SHA256 checksum of the tar.gz archive

## Installation

To install in Termux:
\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/XYenon/amp-cli-termux/main/install.sh | bash
\`\`\`

This is an automated native patch of the official Amp CLI $LATEST_VERSION release for Termux.
See [XYenon/amp-cli-termux](https://github.com/XYenon/amp-cli-termux) for details.
EOF

  gh release create "$LATEST_VERSION" \
    "cli/${LATEST_VERSION}/amp-termux-aarch64.tar.gz" \
    "cli/${LATEST_VERSION}/amp-termux-aarch64.tar.gz.sha256" \
    --target "$VERSION_COMMIT" \
    --title "Amp CLI $LATEST_VERSION (Termux)" \
    --notes-file release_notes.md

  rm release_notes.md
fi
