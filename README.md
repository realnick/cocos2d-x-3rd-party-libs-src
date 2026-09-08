cocos2d-x 3rd party libs
========================

This repository includes the source code of the 3rd party libraries (binary) that are bundled with cocos2d-x.

This repository is needed for cocos2d-x developers and/or people who want to:

* generate a updated version of a certain library (eg: upgrade libpng 1.6.2 to 1.6.14)
* port cocos2d-x to other platforms (eg: port it to Android ARM64, or Tizen, etc)
* generate DEBUG versions of all the 3rd party library


**Note:**

- We use MacOSX to build all the static libraries for iOS, Android, Mac and Tizen.

- We use Ubuntu to build all the static libraries for Linux.

- Windows is not supported yet

Other configuration were not tested. Compiling the Android binaries from a Linux
or Windows machine were not tested, so we don't know if it works or not.

## Download

    $ git clone https://github.com/cocos2d/cocos2d-x-3rd-party-libs-src.git

## Prerequisite
### For Mac users
- If you want to use these scripts, you should install Git 1.8+, CMake 2.8+, autoconf and libtool.
If you are a Homebrew user, you could simply run the following commands to install these tools:

```
brew update
brew install git
brew install cmake
brew install autoconf
brew install automake
brew install libtool
```
**Note:**
If you have an old version autoconf installed, you may need uninstall it first, then reinstall the new version. Directly upgrade to new version by `brew upgrade` command may cause build always failed.

- If you want to build static libraries for iOS and Mac, you should install the latest version of XCode.  You should also install the `Command Line Tools` bundled with XCode.


- If you want to build static libraries for Android, you should install [NDK](https://developer.android.com/tools/sdk/ndk/index.html). NDK r16 is required at the moment and you should also specify the ANDROID_NDK environment variable in your shell.

- If you want to build static libraries for Tizen, you should download and install [Tizen SDK](https://developer.tizen.org/downloads/tizen-sdk). And you should also add a environment variable named `TIZEN_SDK` in your shell.

### For Linux(Ubuntu) users
- If you want to use these scripts, you should instll *autoconf*:

```
sudo apt-get install autoconf
sudo apt-get install automake
sudo apt-get install cmake
sudo apt-get install libtool
sudo apt-get install git
```

- If you want to build 32-bit libs on a 64-bit linux system, you should install *gcc-multilib* and *g++-multilib*

```
sudo apt-get update
sudo apt-get install gcc-multilib
sudo apt-get install g++-multilib
```
Then use command as follow to build 32-bit libs

```
./build.sh -p=platform --libs=libs --arch=i386 --mode=mode
```

### Windows 10 Universal (win10) App users

`build\build_win10_uwp.bat` builds the UWP dependencies with vcpkg and lays them out
in `contrib\install-win10\external\cocos2d-x-deps`;
`install_to_cocos2d_x_uwp.ps1` then copies them into a cocos2d-x working tree.

```
build\build_win10_uwp.bat                 :: win32 + x64 + arm64
build\build_win10_uwp.bat x64             :: one architecture
build\build_win10_uwp.bat win32 arm64     :: a subset
build\build_win10_uwp.bat clean x64       :: wipe the output first
```

Architecture tokens are `win32`, `x64` and `arm64`, matching cocos2d-x's
`prebuilt\win10\<arch>` directories. Set `COCOS_VCPKG_DIR` to use a vcpkg clone
somewhere else.

**ARM32 (`arm-uwp`) is no longer built.** Windows 10 Mobile is gone and the MSVC
toolset in current Visual Studio has no `arm` target — only `arm64`, `x64` and `x86` —
so it cannot be produced any more.

This script used to install a `cocos2d-x-deps` meta-port from the
`stammen/vcpkg-cocos2d-x` fork for x86/x64/arm, while a separate
`build_win10_uwp_arm64.bat` used `microsoft/vcpkg` for arm64 — two different and
widely divergent version sets. The two are now one script on `microsoft/vcpkg` with
the overlay ports, so every UWP architecture, and Windows desktop with it, is
version-aligned as long as they share the vcpkg clone — see
*Upgrading the vcpkg dependency versions* below for how to keep them that way.

Note that the UWP path targets cocos2d-x v3 only.


### Windows desktop (Win32 / x64 / ARM64) users

Building and installing are two steps. `build\build_win32_desktop.bat` builds the
**union** of what cocos2d-x v3 and v4 need with vcpkg, the same way
`build_win10_uwp.bat` does for UWP; `install_to_cocos2d_x_win32.ps1` then
installs the subset for **one** of them into a cocos2d-x working tree.

```
build\build_win32_desktop.bat                 :: win32 + win64 + arm64
build\build_win32_desktop.bat win64           :: one architecture
build\build_win32_desktop.bat win32 arm64     :: a subset
build\build_win32_desktop.bat clean win64     :: wipe the vcpkg clone first

powershell -File build\install_to_cocos2d_x_win32.ps1 -Target v4 -Cocos2dRoot <path>
powershell -File build\install_to_cocos2d_x_win32.ps1 -Target v3 -Cocos2dRoot <path> -Arches win32
```

Architecture tokens are `win32`, `win64` (alias `x64`) and `arm64`; the token is also
the name of the per-architecture output directory. The build clones microsoft/vcpkg
under `contrib\install-win32\vcpkg`; set `COCOS_VCPKG_DIR` to reuse an existing clone
instead.

Two triplets are used per architecture so that each library keeps the linkage
cocos2d-x's existing win32 prebuilts have:

- `<arch>-windows` (DLL + import lib): zlib, openssl, curl, libuv, libwebsockets,
  tiff, sqlite3, libogg, libvorbis, mpg123, openal-soft, glew, libiconv
- `<arch>-windows-static-md` (static lib, dynamic CRT): freetype, libpng,
  libjpeg-turbo, libwebp, glfw3, chipmunk, libwebsockets

libwebsockets is built under both because v4 links the DLL where v3 links a static
`websockets.lib`. `-Target v3` additionally installs tiff and sqlite3; `-Target v4`
additionally installs openssl and libuv. Neither is installed for the other.

Box2D and bullet are **not** built here. cocos2d-x links a single merged
`libbullet.lib` and compiles against its own bundled Box2D/bullet headers, which the
upstream vcpkg ports do not match. v3 builds them from source through project
references (`external\Box2D\proj.win32\libbox2d.vcxproj`); for v4 they would need
pinned overlay ports of their own, the way `vcpkg-overlay-ports\chipmunk` pins
Chipmunk 7.0.1 with `CP_USE_DOUBLES=0` — the version both v3 and v4 bundle headers
for.

Note that the UWP scripts in this directory target v3 only.

**Layout.** Binaries go to `<lib>\prebuilt\<arch>` (`sqlite3\libraries\<arch>` for v3),
and `win32-specific\<lib>\prebuilt` stays flat for win32 with an `<arch>` subdirectory
for the others, because cocos2d-x has it flat today. `win32` therefore lands exactly
where both trees already look and an existing 32-bit build keeps working untouched.

**cocos2d-x side changes** for the new architectures:

- v4 (CMake): `external\cmake\CocosExternalConfig.cmake` has to pick
  `platform_spec_path` by architecture instead of hardcoding `win32`.
- v3 (vcxproj): `cocos\2d\libcocos2d.vcxproj` needs x64 / ARM64 platform
  configurations whose xcopy steps read `prebuilt\<arch>\` instead of `prebuilt\win32\`.

A few file names also differ from what cocos2d-x hardcodes and have to be followed on
the engine side — openssl 3.x DLLs (`libcrypto-3-x64.dll`, not `libcrypto-1_1.dll`),
the ogg/vorbis, iconv and zlib DLLs (`ogg.dll` / `iconv-2.dll` / `z.dll`, not the
`lib*` / `zlib1` names) and `libsharpyuv.lib`, which recent libwebp splits out and
must be linked alongside `libwebp.lib`. The install script prints every rename and every file it could not find
at the end of each run.

### versions.json — which versions this repo currently produces

`versions.json` at the repo root is the one place that answers "what are we
shipping", across every platform. Regenerate it after a Windows build and commit
the result:

```
build/record_versions.sh              # regenerate
build/record_versions.sh --verify     # compare the two halves, exit 1 on drift
```

It is a **lockfile: generated only, never hand-edited**. Bump a version in a
recipe, re-run the generator, commit both. Run it with any bash, including
macOS's stock 3.2.

Where you run it decides which half is recomputed. With a vcpkg clone present
(the Windows machine) both halves are read fresh. Without one — the mac and
Linux machines, which only have the contrib toolchains — the vcpkg half is
carried forward verbatim out of the `versions.json` already in the repo and
only the contrib half is recomputed, so a contrib-only bump can be locked in
from the machine that made it without blanking the Windows pin. That path
parses the existing file with `jq`, so install it there (`brew install jq`).

It exists because the two halves of this repo pin versions in completely
different ways:

| toolchain | platforms | where the version lives |
|---|---|---|
| vcpkg | win32 desktop, win10 UWP | the vcpkg clone's git commit, plus `build/vcpkg-overlay-ports/*/vcpkg.json` |
| contrib | ios, tvos, mac, android, linux, tizen | `contrib/src/<library>/rules.mak` |

The contrib versions are already in the repo. **The Windows ones were recorded
nowhere**: the clone is gitignored, so a fresh clone on another machine silently
picks up whatever is newest. `versions.json` closes that — `vcpkg.commit` is the
pin, and `git checkout <commit>` in the clone reproduces that half exactly.

Each library gets one entry naming the version on each side and a `state`:
`aligned`, `diverged`, `vcpkg-only` or `contrib-only`. vcpkg port names and
contrib directory names are mapped onto one canonical name first (`libjpeg-turbo`
and `jpeg` are both `libjpeg`, `tiff` is `libtiff`, and so on), or the two halves
would never line up. `role` separates the libraries cocos2d-x links itself from
the dependencies those drag in.

`--verify` needs nothing but the repo, so the machines that build iOS, Android
and Mac can check whether a recipe is in step with Windows before touching it.
It only compares the upstream version, ignoring a vcpkg `#N` port-version, since
that is a repackaging of the same release.

Raising the contrib recipes was the intended direction — openssl 1.1.1 is EOL,
so pinning Windows back down to it was never an option — and it was done in two
staged rounds, smallest gaps first. Note that these recipes only build on macOS
and Linux, so that work cannot be done from a Windows machine.

Twelve of the fifteen primary libraries built on both sides are aligned:
chipmunk, plus zlib 1.3.2, libpng 1.6.58, freetype 2.14.3, libtiff 4.7.2,
libwebp 1.6.0, glfw 3.4, libuv 1.52.1, openssl 3.6.3, curl 8.21.0,
libwebsockets 4.5.8 and libjpeg-turbo 3.2.0. Every one was built for mac, ios
and android before being locked in.

The three that remain diverged — `glew`, `libiconv` and `sqlite` — are
**linux-only here**: none of them appears in `cfg_all_supported_libraries` in
`build/mac.ini`, `build/ios.ini` or `build/android.ini`, so they are not part of
any android/ios/mac prebuilt and only the linux platform is affected. Raising
them needs a Linux machine to verify on.

**cocos2d-x side changes to follow from these bumps:**

- libwebp 1.3+ splits sharp YUV conversion into its own archive, so
  `libsharpyuv.a` now ships beside `libwebp.a` (`webp_archive_list` in
  `build/main.ini`) and has to be linked alongside it — the same split Windows
  already hit as `libsharpyuv.lib`.
- openssl is 3.x now on every platform, as it already was on Windows. Anything
  in the engine still calling 1.1.1-era APIs has to move with it.
- libuv still ships as `libuv_a.a` even though upstream renamed its static
  archive to plain `libuv.a`, so nothing changes for it on the engine side
  (`uv_original_name` in `build/main.ini`).
- libjpeg is libjpeg-turbo now rather than IJG jpeg, matching Windows. It keeps
  the `libjpeg.a` name and the libjpeg API, so this should be invisible.

**Notes for whoever builds these next:**

- openssl on android is driven off `$ANDROID_NDK_ROOT`, which the recipe points
  at the standalone toolchain `build.sh` generates rather than the NDK itself —
  see the comment in `contrib/src/openssl/rules.mak`. The android openssl build
  was broken outright before this (a patch that no longer applied, on top of a
  target alias whose arch name did not match the NDK layout); it works now.
- Building android from a mac needs `MACOSX_DEPLOYMENT_TARGET` exported, or
  LuaJIT's build refuses to configure its host tool.
- The mac `x86_64` arch does not cross-compile from an Apple Silicon host: the
  build passes `-m64` with no `-arch`, so it silently produces arm64 objects
  labelled x86_64, and the fat-library step then fails on two arm64 slices.
  Build mac `arm64` there.

### Checking an installed tree for DLLs that will not load

```
powershell -File build\check_cocos2d_x_deps.ps1 -Path <cocos2d-x tree or external dir>
powershell -File build\check_cocos2d_x_deps.ps1 -Path contrib\install-win10\external\cocos2d-x-deps
```

It asks every DLL in the tree what it imports and resolves each import against
the tree, **matching the machine type** — an x64 copy does not satisfy the win32
one. Windows system DLLs and the UWP `*_APP.dll` CRT (supplied by the VCLibs
framework package) are excluded. Exit code is 1 when anything is unresolved, so
it can gate a build.

Run it after installing. This catches the failure mode nothing else does: a
transitive DLL that no one links, so the build succeeds and only the *load*
fails — often not at startup but the first time that code path runs. Two real
examples: a shared libtiff pulls in `jpeg62.dll` and `liblzma.dll`, and current
openal-soft pulls in `fmt.dll`. Both are fixed now — libtiff is built as
`tiff[core]` static and `fmt.dll` ships beside `OpenAL32.dll` — but the next
version bump can introduce another one exactly the same way.

When it reports something, there are two ways out: ship the missing DLL beside
the one that needs it, or build that library statically so there is nothing to
load. Prefer static where cocos2d-x deploys by `xcopy *.lib` (v3's libtiff) or
where the extra DLLs have nowhere sensible to live.

Note that installing the DLL is only half the job for v4: it deploys what is
listed in a target's `IMPORTED_LOCATION`, so an extra DLL has to be appended
there in the library's `CMakeLists.txt` — `external\win32-specific\OggDecoder`
already does this for its second and third DLL.

### Upgrading the vcpkg dependency versions (win10 UWP and Windows desktop)

Both `build_win10_uwp.bat` and `build_win32_desktop.bat` use vcpkg in classic mode, so
**the vcpkg clone's git commit is the version pin** — there is no manifest or baseline
file in this repo. Two consequences:

- Both scripts default to the **same clone**, `contrib\install-win10\vcpkg` (the name
  is historical; it is not UWP-specific), and `COCOS_VCPKG_DIR` overrides both. Keep it
  that way. With separate clones the recipes drift apart silently and UWP and desktop
  end up on different versions of curl, openssl, libwebsockets and so on — and because
  vcpkg separates everything by triplet, one clone holding all nine triplets is the
  intended arrangement, not a compromise.
- `vcpkg install` does **not** upgrade a package that is already installed — it just
  reports it as present, in milliseconds. Pulling new ports alone changes nothing; the
  outdated packages have to be rebuilt explicitly. A "build" that finished suspiciously
  fast did nothing at all.

The procedure:

```
:: 0. record what you are on now, so you can roll back
cd contrib\install-win10\vcpkg
git rev-parse HEAD

:: 1. move the ports forward (or `git checkout <commit>` for a specific version set)
git pull
.\bootstrap-vcpkg.bat -disableMetrics

:: 2. see what the pull actually changed (dry run -- it only lists)
vcpkg upgrade --overlay-ports=..\..\..\build\vcpkg-overlay-ports

:: 3. remove the outdated packages, for every triplet the list named
vcpkg remove --recurse --overlay-ports=..\..\..\build\vcpkg-overlay-ports ^
    <port>:<triplet> <port>:<triplet> ...

:: 4. rebuild both platforms so they stay in step
cd ..\..\..\build
build_win10_uwp.bat
build_win32_desktop.bat

:: 5. reinstall into each cocos2d-x working tree
powershell -File install_to_cocos2d_x_uwp.ps1   -DepsRoot <this repo> -Cocos2dRoot <v3 tree>
powershell -File install_to_cocos2d_x_win32.ps1 -Target v3 -Cocos2dRoot <v3 tree>
powershell -File install_to_cocos2d_x_win32.ps1 -Target v4 -Cocos2dRoot <v4 tree>
```

**Do not run `vcpkg upgrade --no-dry-run`.** Use it only as the preview it is in step 2.
Applying it re-resolves every package with its *default* features, which would turn the
`freetype[core]` the desktop build asks for into `freetype[brotli,bzip2,core,png,zlib]`.
cocos2d-x links a single `freetype.lib` and would then fail on unresolved brotli, bz2,
png and zlib symbols. Removing and letting the build scripts reinstall keeps the
feature selection the scripts spell out.

**Never install while a rebuild is in flight.** Between the `vcpkg remove` in step 3 and
the end of step 4 the packages simply do not exist, and the install scripts skip what
they cannot find — leaving the previous version in the cocos2d-x tree and listing it
under "not found in the vcpkg trees". Read that section; a silent stale library is
worse than a failure.

**Read the install script's report.** A version bump is where file names move — that
is how `libsharpyuv.lib` appeared when libwebp split it out, and how openssl went from
`libcrypto-1_1.dll` to `libcrypto-3-<arch>.dll`. The rename list and the "not found"
list printed at the end of each install run are the signal that the cocos2d-x side
needs a matching edit.

**Check that the two platforms agree** afterwards. Every installed package records its
version in the vcpkg tree, so a mismatch is easy to spot:

```powershell
$info = 'contrib\install-win10\vcpkg\installed\vcpkg\info'
function Get-Pkgs($triplet) {
    Get-ChildItem "$info\*_$triplet.list" | ForEach-Object {
        $n = $_.Name -replace "_$triplet\.list$", ''
        [pscustomobject]@{ Name = $n -replace '_[^_]*$', ''; Version = ($n -split '_')[-1] }
    }
}
$uwp = Get-Pkgs 'arm64-uwp'
$win = Get-Pkgs 'x64-windows'
Compare-Object $uwp $win -Property Name, Version |
    Where-Object { $_.Name -in ($uwp.Name | Where-Object { $_ -in $win.Name }) }
```

Anything listed is a package the two platforms disagree on. An empty result means they
are in step.

**Overlay ports are pinned separately.** `build\vcpkg-overlay-ports\` holds chipmunk,
freetype, libwebsockets and sqlite3, and a `git pull` does not touch them — their
versions live in each port's `vcpkg.json`, with the source hash in `portfile.cmake`.
Upgrading one means editing both.

**Editing an overlay port requires bumping its `port-version`.** vcpkg decides whether
an installed package is current by comparing version and port-version, *not* by hashing
the recipe. Change a portfile or a patch without bumping `port-version` and every
subsequent `vcpkg install` reports the package as already installed and does nothing —
the edit silently never takes effect, and `vcpkg upgrade` reports everything as
up-to-date. Bump it, confirm with `vcpkg upgrade --overlay-ports=...` that the package
now appears in the rebuild list, then follow steps 3 to 5 above.

The same trap catches a *newly added* overlay port: a package already installed from the
builtin port is not rebuilt just because an overlay for it appeared, so it keeps
whatever the builtin recipe produced until its port-version moves past the installed
one.

Chipmunk in particular is pinned deliberately: cocos2d-x compiles its physics code
against its own bundled headers (7.0.1 with `CP_USE_DOUBLES=0`, the same in the v3 and
v4 trees), and the prebuilt library is only linked, never re-declared. Building a
different Chipmunk makes every `cpVect`/`cpFloat` crossing the ABI the wrong size —
which is a silent crash, not a link error. Do not move it without changing the
cocos2d-x headers to match.

### For Windows (Win32) App users, by hand

To build static libraries for Win32 is straightfoward, you could just setup a new static libary project with VisualStudio
and import all the needed source files and header files into the project.

Note: Some libraries use configure system to generate the required header files for Windows platform. If you find some 
header files are missing, please check the README file of the 3rd libs. In general, it will provide a VS project to 
build the static libs for Windows. Some libs also provide a CMakeLists.txt file, you could use CMake GUI tool to generate
a static library project. Don't forgt to Google the error messages when you can't compile the libs successfully.

### For Tizen Users
To build static libraries for Tizen, you should install Tizen Studio at first. At the time of writing, the latest version of Tizen Studio is v1.1.0, you could download it from
[here](https://developer.tizen.org/development/tizen-studio/download?langswitch=en).

Note: By default, we use Tizen SDK 2.4 to build static libs. If you want to build static libraries with other Tizen SDK version, you should change `cfg_default_tizen_sdk_version` in `tizen.ini` file.

After downloading the Tizen Studio, you should also install the native packages with the **Tizen Update Manager** from the `Tools/Package Manager` menu in Tizen Studio.

When finished the above setup, you should set a **TIZEN_STUDIO_HOME** environment variable to your shell configure file. (Normally .bash_profile for bash and .zshrc for zsh).

## How to use
We have one build script for each platform, it is under `build` directory.

The usage would be:

```
./build.sh -p=platform --libs=libs --arch=arch --mode=mode --list
```

- platform: specify a platform. Supported platforms: ios, mac, android, linux and tizen

  libs:
    - use `all` to build all the 3rd party libraries.
    - use comma separated library names, for example, `png,lua,jpeg,webp`, no space between the comma to select one or more libs

  arch:
    - use `all` to build all the supported architectures.
    - for iOS, they are "armv7, arm64, i386, x86_64"
    - for Android, they are "arm,armv7,arm64,x86"
    - for Mac, they are "x86_64"
    - for Tizen, they are "armv7"
    - use comma separated arch name, for example, `armv7, arm64`, no space between the comma.

- mode:
    - release:  Build library on release mode. This is the default option. We use `-O3 -DNDEBUG` flags to build release library.
    - debug:  Build library on debug mode. we use `-O0 -g -DDEBUG` flag to build debug library.

- list:
    - Use these option to list all the supported library names and versions.

### Build png on iOS platform
For building libpng fat library with all arch x86_64, i386, armv7, arm64 on release mode:

```
cd build
./build.sh -p=ios --libs=png
```

After running this command, it will generate a folder named `png`:

The folder structure would be:

```
-png
--include(this folder contains the exported header files)
- prebuilt(this folder contains the fat library)
```

All the other libraries share the same folder structure.

For building libpng fat library with arch armv7 and arm64 on debug mode:

```
cd build
./build.sh -p=ios --libs=png --arch=armv7,arm64 --mode=debug
```

### Build for Android arm64

1. Download Android NDK r10c+ and set the ANDROID_NDK to point to the Android NDK path. Don't forget to `source ~/.bash_profile`.

2. Make sure the `cfg_default_arm64_build_api` is 21+(The default is 21) and `cfg_default_gcc_version` is 4.9 in  android.ini config.

3. Pass `--arch=arm64` to build the libraries with arm64 support.

Note:
If you build `webp` with arm64, you will get `cpu-features.h` header file not found error. This is a known issue of Android NDK r10c. You could simply create a empty header file
named `cpu-features.h` under `{ANDROID_NDK}/platforms/android-21/arch-arm64/usr/include`.

### Enable bitcode for iOS
On default, when building static libs for TVOS, it will enable bitcode, but iOS doesn't.

You should change `cgf_build_bitcode` in `ios.ini` to `-fembed-bitcode`.

Here is the example code:

```
cfg_build_bitcode="-fembed-bitcode"
```

## How to build a DEBUG and RELEASE version
You can add flag "--mode=[debug | release]" for building DEBUG and RELEASE version.

## How to do build clean?
You could simply turn on the flag `cfg_is_cleanup_after_build` to "yes" in `main.ini` file.
After each build, you could also delete the generated folders under `contrib` directory.


## How to upgrade a existing library
If you find a 3rd party library has some critical bug fix, you might need to update it.
You can following the [README](./contrib/src/README) file to do this job.

## How to add new 3rd party libraries
Please refer to [README](./contrib/src/README)
