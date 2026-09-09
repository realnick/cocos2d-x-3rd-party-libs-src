# Quick start

The short version: what this repo currently produces, how to build it, how to
install it. Everything else — per-platform detail, the vcpkg workflow, adding a
library — is in [README.md](README.md).

## What it produces

Two toolchains, split by platform:

| platform | toolchain | version pinned in | built on |
|---|---|---|---|
| ios, tvos, mac, android, linux, tizen | contrib | `contrib/src/<lib>/rules.mak` | macOS or Linux |
| win32 desktop, win10 UWP | vcpkg | the vcpkg clone's git commit | Windows |

`versions.json` records both halves. Current versions, identical on both sides:

| library | version | | library | version |
|---|---|---|---|---|
| openssl | 3.6.3 | | libpng | 1.6.58 |
| curl | 8.21.0 | | libjpeg | libjpeg-turbo 3.2.0 |
| libwebsockets | 4.5.8 | | libwebp | 1.6.0 |
| libuv | 1.52.1 | | libtiff | 4.7.2 |
| zlib | 1.3.2 | | freetype | 2.14.3 |
| chipmunk | 7.0.1 | | glfw | 3.4 (mac/win only) |

Still behind Windows: `glew` 1.7.0, `libiconv` 1.14, `sqlite` 3.6.20 — all
three are **linux-only** here, so no android, ios or mac prebuilt is affected.
Contrib-only: `box2d`, `bullet`, `lua`, `luajit`, `rapidjson`,
`glsl_optimizer`. Windows-only: `libogg`, `libvorbis`, `mpg123`, `openal-soft`.

```
build/record_versions.sh            # regenerate versions.json after a bump
build/record_versions.sh --verify   # exit 1 if the two toolchains disagree
```

`versions.json` is generated, never hand-edited. Run the generator on the
machine that made the change and commit the result: without a vcpkg clone it
carries the Windows half forward untouched and recomputes only contrib (that
path needs `jq`).

## Build

Xcode, plus `cmake` `autoconf` `automake` `libtool` `jq` from Homebrew. Android
also needs NDK r16 pointed at by `ANDROID_NDK`. Then `cd build`.

**mac** — universal (x86_64 + arm64):

```bash
./build.sh -p=mac --libs=all --arch=all
```

**android**:

```bash
export ANDROID_NDK=$HOME/Library/Android/sdk/ndk/16.1.4479499
export MACOSX_DEPLOYMENT_TARGET=15.0
./build.sh -p=android --libs=all --arch=all      # armv7, x86, arm64
./build.sh -p=android --libs=all --arch=x86_64   # "all" does not include it
```

`MACOSX_DEPLOYMENT_TARGET` is only for LuaJIT, which builds a host-side tool and
refuses to configure on macOS without it.

**ios** — *not* `build.sh -p=ios`. Both cocos2d-x trees take `.xcframework`
bundles for iOS, and only this script produces them: device and simulator share
the arch name `arm64` but are different platforms, so they are built separately
and packaged together.

```bash
env -u MACOSX_DEPLOYMENT_TARGET ./build_ios_xcframeworks.sh
./build_ios_xcframeworks.sh --libs=jpeg,chipmunk   # a subset
./build_ios_xcframeworks.sh --skip-build           # re-package only
```

Unset `MACOSX_DEPLOYMENT_TARGET` for iOS: CMake reuses it as the iOS deployment
target, and 32-bit iOS caps at 10, so libuv fails to configure with it set. Run
android and iOS from different shells, or use `env -u` as above.

**windows**, from a Windows machine: `build\build_win32_desktop.bat` and
`build\build_win10_uwp.bat`. **linux** and **tizen** use `build.sh` like mac.

## Install into a cocos2d-x tree

One installer per toolchain: a shell script for android/ios/mac, PowerShell for
the two Windows targets. All of them take the root of the cocos2d-x tree (the
directory holding `external\`).

**android / ios / mac**

```bash
build/install_to_cocos2d_x_contrib.sh --target v3 --cocos2d-root <tree> --dry-run
build/install_to_cocos2d_x_contrib.sh --target v3 --cocos2d-root <tree>
build/install_to_cocos2d_x_contrib.sh --target v4 --cocos2d-root <tree>
```

`--platforms android,ios,mac` narrows it; `--dry-run` prints every copy without
making one. iOS is taken from `build/xcframeworks/`, so build that first — the
script warns if those bundles predate a recipe change.

**win32 desktop** — `-Target` picks which engine's subset, linkage and file
names to install; `-Arches` defaults to all three:

```powershell
powershell -File build\install_to_cocos2d_x_win32.ps1 -Target v3 -Cocos2dRoot <tree>
powershell -File build\install_to_cocos2d_x_win32.ps1 -Target v4 -Cocos2dRoot <tree>
powershell -File build\install_to_cocos2d_x_win32.ps1 -Target v3 -Cocos2dRoot <tree> -Arches win32
```

**win10 UWP** — v3 only, and it copies from this repo's staged output rather
than from vcpkg directly, so it needs both roots:

```powershell
powershell -File build\install_to_cocos2d_x_uwp.ps1 -DepsRoot <this repo> -Cocos2dRoot <tree>
powershell -File build\install_to_cocos2d_x_uwp.ps1 -DepsRoot <this repo> -Cocos2dRoot <tree> -Arches x64
```

Both PowerShell scripts print every file they installed under a different name,
and every file they could not find, at the end of the run — read that list, it
is how a renamed DLL or a half-finished build shows up. `check_cocos2d_x_deps.ps1`
then verifies the installed DLLs can actually resolve their imports.

`--target` / `-Target` matters because the two engine trees disagree about
where things live:

| | v3 | v4 |
|---|---|---|
| openssl (android/ios/mac) | `external/curl/prebuilt/` | `external/openssl/prebuilt/` |
| libuv (android/ios/mac) | `external/websockets/prebuilt/` | `external/uv/prebuilt/` |
| tiff | installed | not in the tree |
| Box2D / bullet / glsl-optimizer | built from source | installed |
| libwebsockets (win32) | static `websockets.lib` | the DLL |
| sqlite3 (win32) | `sqlite3\libraries\<arch>` | not installed |

Headers that cocos2d-x keeps in one shared `include/` for every platform —
zlib, chipmunk, uv, Box2D, bullet, glsl-optimizer — are deliberately not
written, since one platform's copy would misconfigure the others.

## After installing: what the engine side needs

- **Link `libsharpyuv.a` next to `libwebp.a`.** libwebp 1.3+ split sharp YUV
  conversion into its own archive. Windows hit the same split as
  `libsharpyuv.lib`.
- **openssl is 3.x everywhere now.** Anything still calling 1.1.1-era APIs has
  to move with it.
- **libwebsockets is 4.x**, which is not source compatible with the 2.x it
  replaces. Its `libwebsockets.h` includes the `libwebsockets/` directory that
  now ships beside it.
- **32-bit android (armeabi-v7a, x86) needs `-latomic`.** openssl 3.x uses
  64-bit atomics, which are libatomic calls there rather than instructions.
- libuv still ships as `libuv_a.a` and libjpeg-turbo still as `libjpeg.a`, so
  neither needs an engine-side change.
- **On Windows, several DLL names differ from what cocos2d-x hardcodes** —
  `libcrypto-3-<arch>.dll` rather than `libcrypto-1_1.dll`, `ogg.dll` /
  `iconv-2.dll` / `z.dll` rather than the `lib*` and `zlib1` names — and the new
  architectures need project changes of their own. README.md lists them per
  engine version.

## Gotchas when rebuilding

- **Changing a flag does not force a rebuild.** The per-arch source tree under
  `contrib/<platform>-<arch>/<lib>/` is reused, and LuaJIT in particular will
  relink stale objects of the previous architecture. Delete that directory (and
  the `.<lib>` stamp) when you change how something is built.
- `contrib/<platform>-<arch>/toolchain.cmake` is likewise only generated when
  missing. Delete it after changing the flags it carries.
- **mac `x86_64` from an Apple Silicon host** works, but only because every
  build path names the architecture explicitly. If you add a library, make sure
  its build honours `-arch`/`CMAKE_OSX_ARCHITECTURES` — `-m64` alone silently
  produces arm64 objects filed under x86_64, and the fat-library step then
  fails on two arm64 slices.
- **32-bit arm and x86 need openssl's `no-asm`.** Its armv7 assembly does not
  assemble with clang's integrated assembler, and its x86_64 AVX-512 paths are
  newer than the NDK r16 assembler.
