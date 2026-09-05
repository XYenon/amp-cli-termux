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

RELEASE_ASSETS=(
  "cli/${LATEST_VERSION}/amp"
  "cli/${LATEST_VERSION}/bun"
  "cli/${LATEST_VERSION}/bun-shim.so"
  "cli/${LATEST_VERSION}/sha256sums.txt"
)

# Create GitHub Release or upload assets (use --clobber to overwrite if exists).
# --target pins the tag to the version-file commit instead of the previous commit.
if gh release view "$LATEST_VERSION" >/dev/null 2>&1; then
  echo "Release already exists. Uploading assets with --clobber..."
  gh release upload "$LATEST_VERSION" "${RELEASE_ASSETS[@]}" --clobber
else
  echo "Creating new release..."

  cat <<EOF > release_notes.md
Automated patched release of Amp CLI $LATEST_VERSION for native Termux (ARM64/aarch64).

## Assets

- \`amp\` - Patched Amp CLI binary
- \`bun\` - Amp-private \`bun-termux\` compatibility wrapper
- \`bun-shim.so\` - Amp-private \`LD_PRELOAD\` compatibility shim
- \`sha256sums.txt\` - SHA256 checksums of all release files

Amp's glibc compatibility components are isolated under \`~/.amp/runtime\`
until Amp ships an Android/Bionic build of its bundled native addons. The
installer does not install or modify the user's Bun.

## Installation

To install in Termux:
\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/XYenon/amp-cli-termux/main/install.sh | bash
\`\`\`

This is an automated native patch of the official Amp CLI $LATEST_VERSION release for Termux.
See [XYenon/amp-cli-termux](https://github.com/XYenon/amp-cli-termux) for details.
EOF

  gh release create "$LATEST_VERSION" \
    "${RELEASE_ASSETS[@]}" \
    --target "$VERSION_COMMIT" \
    --title "Amp CLI $LATEST_VERSION (Termux)" \
    --notes-file release_notes.md

  rm release_notes.md
fi
