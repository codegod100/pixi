#!/usr/bin/env bash
# Cross-compile pixi for Termux (aarch64-linux-android) on an x86_64 Linux host.
#
# Needs: rustup/cargo, git, python3, and an Android NDK (r27+ works; tested with r30).
#   ANDROID_NDK_HOME=/path/to/android-ndk ./build-pixi-termux.sh [pixi-git-ref]
#
# Output: pixi/target/aarch64-linux-android/ci/pixi
set -euo pipefail

REF="${1:-b71aebc0a5c28cd3c7199e4726b7d388ad2b6a42}"
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${WORK:-$PWD/pixi-termux-build}"
: "${ANDROID_NDK_HOME:?set ANDROID_NDK_HOME to an Android NDK}"
API=24
TC="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"

mkdir -p "$WORK" && cd "$WORK"
[ -d pixi ] || git clone https://github.com/prefix-dev/pixi.git
cd pixi
git fetch --depth 1 origin "$REF" 2>/dev/null || true
git checkout -f "$REF"

# 1. Small source fixes (trampoline + ptsname_r on Android)
git apply "$HERE/pixi-android.patch"

rustup target add aarch64-linux-android
cargo fetch
REG=$(ls -d "${CARGO_HOME:-$HOME/.cargo}"/registry/src/index.crates.io-*/ | head -1)
VEND="$WORK/vendor"; rm -rf "$VEND"; mkdir -p "$VEND"

# 2. rustls-platform-verifier: its Android backend needs JNI init from an APK.
#    Same trick as termux-packages' uv recipe: build the generic Unix backend.
PATCH_LINES=""
# Exact versions from Cargo.lock (a glob would also match e.g. rustls-platform-verifier-android).
lock_versions() { awk -v n="$1" '$0=="name = \""n"\"" {getline; gsub(/version = |"/,""); print}' Cargo.lock; }

for v in $(lock_versions rustls-platform-verifier); do
  dir="$REG/rustls-platform-verifier-$v"
  cp -r "$dir" "$VEND/rpv-$v"
  find "$VEND/rpv-$v" -type f -print0 | xargs -0 sed -i \
    -e 's|"android"|"disabling_this_because_it_is_for_building_an_apk"|g'
  PATCH_LINES+="rustls-platform-verifier-${v//./_} = { path = \"$VEND/rpv-$v\", package = \"rustls-platform-verifier\" }"$'\n'
done

# 3. libdbus-sys (vendored, for the keyring): build Android like Linux.
for v in $(lock_versions libdbus-sys); do
  dir="$REG/libdbus-sys-$v"
  cp -r "$dir" "$VEND/libdbus-sys-$v"
  sed -i 's|Ok("linux") => {|Ok("linux") \| Ok("android") => {|' "$VEND/libdbus-sys-$v/build_vendored.rs"
  PATCH_LINES+="libdbus-sys-${v//./_} = { path = \"$VEND/libdbus-sys-$v\", package = \"libdbus-sys\" }"$'\n'
done

python3 - "$PATCH_LINES" <<'EOF'
import sys
lines = sys.argv[1]
s = open("Cargo.toml").read()
s = s.replace("[patch.crates-io]\n", "[patch.crates-io]\n" + lines, 1)
open("Cargo.toml", "w").write(s)
EOF

export CC_aarch64_linux_android="$TC/aarch64-linux-android$API-clang"
export CXX_aarch64_linux_android="$TC/aarch64-linux-android$API-clang++"
export AR_aarch64_linux_android="$TC/llvm-ar"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$TC/aarch64-linux-android$API-clang"
export PKG_CONFIG_ALL_DYNAMIC=1

# "ci" profile = optimized, no LTO (the full release profile is much slower to build)
cargo build --target aarch64-linux-android --profile ci -p pixi
"$TC/llvm-strip" target/aarch64-linux-android/ci/pixi
ls -la target/aarch64-linux-android/ci/pixi
