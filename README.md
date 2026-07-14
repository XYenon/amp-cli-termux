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
3. **Automated Updates**: The compiled wrapper intercepts the `update` subcommand natively, fetching and executing the installation script to atomically update the `amp` binary, the wrapper, and the shim without interrupting shell execution.

---

## Auto-Update

- **GitHub Action Schedule**: Every 6 hours, the workflow `.github/workflows/repatch.yml` checks for new official Amp CLI versions. If a new version is found, it will automatically download, patch, and release it on GitHub Releases, and update `cli/cli-version.txt`.
- **Client Auto-Update**: When you run `amp update`, the wrapper intercepts the command and executes the installation script to update the `amp` binary, wrapper (`bun`), and helper libraries atomically.

## Credits

- **`bun-termux`**: [Happ1ness-dev/bun-termux](https://github.com/Happ1ness-dev/bun-termux)
- **`bun-termux-loader`**: [kaan-escober/bun-termux-loader](https://github.com/kaan-escober/bun-termux-loader)
