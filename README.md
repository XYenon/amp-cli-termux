# Amp CLI Termux Standalone Port

[![Auto Patch Update](https://github.com/XYenon/amp-cli-termux/actions/workflows/repatch.yml/badge.svg)](https://github.com/XYenon/amp-cli-termux/actions/workflows/repatch.yml)

Termux-compatible standalone port of **Amp CLI** (`amp` from [ampcode.com](https://ampcode.com)).

Inspired by [antigravity-cli-termux](https://github.com/wallentx/antigravity-cli-termux) which does the same for Google Antigravity CLI.

Runs **natively** on Termux **without** requiring a `proot-distro` container. Fully compatible with all Amp plugins and skills.

---

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/XYenon/amp-cli-termux/main/install.sh | bash
```

> **Note**: Only **ARM64/aarch64** is supported (all modern Android devices).
>
> If `amp` is not found after installation:
>
> ```bash
> echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
> ```

---

## How it works

1. **Amp-private compatibility runtime**: Amp currently embeds a Linux/glibc keyring native addon, so a private `bun-termux` wrapper + `LD_PRELOAD` shim handles:
   - Path translation from `/bin` → Termux `$PREFIX/bin`
   - DNS configuration (`resolv.conf`) for glibc
   - Shebang fixing for scripts (`#!/bin/sh` → Termux paths)
   - System call intercepts for cross-environment compatibility

2. **Binary Patching**: GitHub Action automatically patches new Amp releases:
   - Downloads official `amp-linux-arm64` from ampcode.com
   - Extracts the embedded Bun JS payload
   - Repackages with the `bun-termux` wrapper (supports both old and new Bun executable formats)

3. **Auto-Update**: The wrapper intercepts the `amp update` command and runs the installer script atomically to update all components.

---

## Installation Layout

| Component | Location | Purpose |
| --------- | -------- | ------- |
| `amp` | `~/.amp/bin/amp` | Patched Amp CLI binary |
| `bun-termux` | `~/.amp/runtime/bin/bun` | Amp-private wrapper that executes glibc Bun |
| `buno` | `~/.amp/runtime/bin/buno` | Amp-private unmodified glibc Bun |
| `bun-shim.so` | `~/.amp/runtime/lib/bun-shim.so` | Amp-private `LD_PRELOAD` compatibility shim |
| wrapper | `~/.local/bin/amp` | Shell wrapper selecting Amp's private runtime |

---

## Auto-Update

- **Server-side**: GitHub Action checks for new official Amp releases every 6 hours, patches and publishes automatically
- **Client-side**: Run `amp update` to pull and install the latest version atomically

---

## Troubleshooting

- **Why does Amp still use glibc?** Bun supports Android natively, but the current Amp Linux artifact embeds a glibc keyring addon. The compatibility runtime will be removed once Amp ships an Android/Bionic build. The installer does not install or modify the user's Bun.
- **`command not found`**: Add `~/.local/bin` to your `PATH` (see note above)
- **DNS resolution fails**: The installer configures public DNS by default. Check `$PREFIX/etc/resolv.conf` and `$PREFIX/glibc/etc/resolv.conf` if you have custom network settings

---

## Credits

- Original `bun-termux` work: [Happ1ness-dev/bun-termux](https://github.com/Happ1ness-dev/bun-termux)
- Binary patching technique: [kaan-escober/bun-termux-loader](https://github.com/kaan-escober/bun-termux-loader)
- Amp CLI: [ampcode.com](https://ampcode.com)
