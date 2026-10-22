# pixi for Termux (aarch64)

A native Android/Bionic build of pixi 0.82.1 (prefix-dev/pixi @ b71aebc), cross-compiled with NDK r30, API 24.

## Install on the phone

```sh
curl -fL https://raw.githubusercontent.com/codegod100/pixi/termux/pixi-aarch64-linux-android.gz | gunzip > $PREFIX/bin/pixi && chmod +x $PREFIX/bin/pixi && pixi --version
```

## What works (tested in the aarch64 termux-docker image under qemu)

- `pixi --version`, `pixi info` (reports platform `android-aarch64`)
- `pixi init`, `pixi task add`, `pixi run <task>` (tasks run fine with Termux's
  default termux-exec, which rewrites `/usr/bin/env` in the activation script)
- `pixi search`, solving and downloading from conda-forge over HTTPS (uses the bundled Mozilla roots;
  behind a corporate/MITM proxy set `SSL_CERT_FILE=$PREFIX/etc/tls/cert.pem`)
- `pixi install --platform linux-aarch64` downloads and extracts a linux-aarch64 env

## What doesn't (and why)

- **conda-forge has no `android-aarch64` subdir** (404), so `pixi add python` on the
  native platform finds nothing. Only noarch packages or your own android-aarch64 channel would solve.
- **linux-aarch64 packages are glibc binaries.** They download, but don't run on Bionic
  (`/lib/ld-linux-aarch64.so.1` is missing). pixi also refuses to install them as the
  default env unless you pass `--platform linux-aarch64`.
  Options: Termux's `glibc-runner` (`pkg install glibc-repo && pkg install glibc-runner`, then `grun`), untested here,
  or run the official linux-aarch64 pixi inside `proot-distro`, which works the normal way.

So the native build is good for task running and managing workspaces, but for actual
conda packages on the phone, proot-distro with the official pixi is still the practical route.

## Patches needed

1. `pixi-android.patch`: embed a PIE Bionic trampoline for `pixi global` on Android
   (the static musl one fails with `unexpected e_type: 2`, because termux-exec launches
   binaries through `/system/bin/linker64`); enable `nix::pty::ptsname_r` on Android.
   The patch is binary (`git apply` handles it), since it adds
   `trampoline/binaries/pixi-trampoline-aarch64-linux-android.zst`.
2. `rustls-platform-verifier`: its Android backend needs JNI init from an APK, so it's
   patched to use the generic Unix backend (same trick as termux-packages' `uv` recipe).
3. `libdbus-sys` (vendored, pulled in by the keyring): build script rejects Android;
   treat it like Linux.

`build-pixi-termux.sh` does all of this from a clean clone
(`ANDROID_NDK_HOME=... bash build-pixi-termux.sh`). A cold build takes about 20 minutes on 4 cores with the `ci` profile.
