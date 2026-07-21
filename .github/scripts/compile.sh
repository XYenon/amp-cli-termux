#!/usr/bin/env bash
set -e

# Compile bun-termux wrapper (Android Bionic) using NDK cross-compiler
"$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/linux-x86_64/bin/clang \
  --target=aarch64-linux-android24 -O3 -Wl,-z,norelro \
  -DAMP_REPO="\"$GITHUB_REPOSITORY\"" \
  -o bun bun-termux.c

# Compile bun-shim (glibc) using GNU cross-compiler
aarch64-linux-gnu-gcc -shared -fPIC -O3 -o bun-shim.so shim.c -ldl
