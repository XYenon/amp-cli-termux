# Amp CLI Termux Standalone Port

This repository provides a Termux-compatible standalone port of the **Amp CLI** (`amp` from [ampcode.com](https://ampcode.com)), similar to how [antigravity-cli-termux](https://github.com/wallentx/antigravity-cli-termux) handles the Google Antigravity CLI.

It runs **natively** in Termux without requiring a full `proot-distro` container, and it is fully compatible with Amp plugins/skills.

---

## Installation in Termux

To install the patched Amp CLI in Termux, run:

```bash
curl -fsSL https://raw.githubusercontent.com/XYenon/amp-cli-termux/main/install.sh | bash
```

---

## How it works

1. **`bun-termux` Wrapper & Shim**: We use a custom C-compiled wrapper (`bun-termux`) and an `LD_PRELOAD` shim (`bun-shim.so`) originally developed by the Termux community (`Happ1ness-dev/bun-termux`). This maps paths, wraps DNS files, handles shebangs (like `/bin/sh`), and intercepts system calls natively.
2. **Binary Patching**: When a new version of Amp CLI is released, the GitHub Action automatically downloads it, extracts the JS bundle payload, and repackages it using the `bun-termux` wrapper.
3. **Automated Updates**: By setting the `AMP_STORAGE_BASE` environment variable in the wrapper script, the patched Amp binary redirects all version checks and updates to **this repository**. When Amp auto-updates, it pulls pre-patched binaries directly from your repo!

---

## Auto-Update

- **GitHub Action Schedule**: Every 6 hours, the workflow `.github/workflows/repatch.yml` checks for new official Amp CLI versions. If a new version is found, it will automatically download, patch, and release it on GitHub Releases, and update `cli/cli-version.txt`.
- **Client Auto-Update**: When you run `amp update` or it auto-updates, it will query your repo's `cli/cli-version.txt` and download the pre-patched binary from your repo's GitHub Releases.

## Credits

- **`bun-termux`**: [Happ1ness-dev/bun-termux](https://github.com/Happ1ness-dev/bun-termux)
- **`bun-termux-loader`**: [kaan-escober/bun-termux-loader](https://github.com/kaan-escober/bun-termux-loader)
