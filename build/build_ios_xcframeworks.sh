#!/bin/bash
# Build every iOS prebuilt library for both device and simulator arch sets,
# then package each resulting static library as an .xcframework.
#
# Device (armv7/armv7s/arm64) and simulator (i386/x86_64/arm64_simulator)
# builds are run as SEPARATE build.sh invocations, never combined into one
# fat lib: the simulator's arm64 slice (Apple Silicon Simulator) and the
# device's arm64 slice are semantically different platforms that happen to
# share the literal arch name "arm64", and lipo refuses to hold two slices
# with the same architecture in one file. .xcframework is what lets Xcode
# pick the right variant per-platform without ambiguity.
#
# Usage:
#   ./build_ios_xcframeworks.sh                       # build+package everything
#   ./build_ios_xcframeworks.sh --libs=jpeg,chipmunk   # only these libraries
#   ./build_ios_xcframeworks.sh --skip-build           # package only, using
#                                                       # whatever ios/*/prebuilt-*
#                                                       # dirs already exist
set -e

cd "$(dirname "$0")"

DEVICE_ARCHES="armv7,armv7s,arm64"
SIMULATOR_ARCHES="i386,x86_64,arm64_simulator"

# LuaJIT can't be cross-built for 32-bit targets from an Apple Silicon host:
# its buildvm HOST tool must match the TARGET's pointer size, and current
# macOS can no longer produce a 32-bit host binary at all (Apple dropped
# 32-bit host support outright). Building 32-bit iOS binaries in general
# still works (see contrib/bootstrap's IOS_LEGACY_XCODE_DEVELOPER_DIR), but
# LuaJIT's cross-build tooling itself is the thing that can't run 32-bit,
# not the target - so this one library is skipped for armv7/armv7s/i386.
LUAJIT_DEVICE_ARCHES="arm64"
LUAJIT_SIMULATOR_ARCHES="x86_64,arm64_simulator"

# rapidjson is header-only (no .a); it's still built so its headers get
# copied into ios/rapidjson/include, but the packaging step below skips it.
ALL_LIBS="png zlib lua luajit websockets curl freetype jpeg tiff webp chipmunk openssl rapidjson bullet box2d uv glsl_optimizer"

BUILD_LIBS=""
SKIP_BUILD=no
for arg in "$@"; do
  case "$arg" in
    --libs=*) BUILD_LIBS="${arg#--libs=}" ;;
    --skip-build) SKIP_BUILD=yes ;;
    *) echo "unknown argument: $arg" >&2; exit 1 ;;
  esac
done
[ -z "$BUILD_LIBS" ] && BUILD_LIBS="$ALL_LIBS"
BUILD_LIBS="${BUILD_LIBS//,/ }"

# Build one library for one platform's arch set, then move the resulting
# top-level .a files (and any dependent archives it drags in, e.g. openssl's
# libssl.a pulling in libcrypto.a under a sibling ios/crypto/ dir) out of
# ios/<lib>/prebuilt/ into ios/<lib>/prebuilt-<platform>/ so the next
# platform's build starts from a clean prebuilt/ directory.
build_platform() {
  local lib="$1" platform="$2" arches="$3"

  IFS=',' read -ra arch_list <<< "$arches"
  for a in "${arch_list[@]}"; do
    rm -rf "../contrib/ios-$a"
  done

  env -u SDKROOT ./build.sh -p=ios --libs="$lib" -a="$arches" -m=release

  find ios -mindepth 3 -maxdepth 3 -path "*/prebuilt/*.a" | while read -r f; do
    local dir base target
    dir=$(dirname "$f")
    base=$(dirname "$dir")
    target="$base/prebuilt-$platform"
    mkdir -p "$target"
    mv "$f" "$target/"
  done

  find ios -mindepth 3 -maxdepth 4 -type d -path "*/prebuilt/*" -exec rm -rf {} +
}

if [ "$SKIP_BUILD" = "no" ]; then
  for lib in $BUILD_LIBS; do
    device_arches="$DEVICE_ARCHES"
    simulator_arches="$SIMULATOR_ARCHES"
    if [ "$lib" = "luajit" ]; then
      device_arches="$LUAJIT_DEVICE_ARCHES"
      simulator_arches="$LUAJIT_SIMULATOR_ARCHES"
    fi
    echo "=== $lib (device: $device_arches) ==="
    build_platform "$lib" device "$device_arches"
    echo "=== $lib (simulator: $simulator_arches) ==="
    build_platform "$lib" simulator "$simulator_arches"
  done
fi

# Package: auto-discover every archive that has both a device and simulator
# build, pairing by archive filename. Some libraries produce more than one
# .a (e.g. bullet, glsl_optimizer) and some archives get copied into more
# than one lib's prebuilt dir as a dependency (e.g. libuv_a.a lands under
# both ios/uv/ and ios/uv_a/) - when that happens, prefer whichever source
# directory actually carries headers, since that's the "real" owner.
OUT="xcframeworks"
rm -rf "$OUT"
mkdir -p "$OUT"

# macOS ships bash 3.2 (no associative arrays), so track archive->lib choices
# in a plain "archive:lib" list file instead of declare -A.
choices_file=$(mktemp)
trap 'rm -f "$choices_file"' EXIT

while IFS= read -r dev_a; do
  lib_dir=$(dirname "$(dirname "$dev_a")")
  lib=$(basename "$lib_dir")
  archive=$(basename "$dev_a")

  chosen=$(grep "^$archive:" "$choices_file" 2>/dev/null | tail -1 | cut -d: -f2)
  if [ -z "$chosen" ]; then
    echo "$archive:$lib" >> "$choices_file"
  elif [ -d "ios/$lib/include" ] && [ ! -d "ios/$chosen/include" ]; then
    grep -v "^$archive:" "$choices_file" > "$choices_file.tmp" || true
    mv "$choices_file.tmp" "$choices_file"
    echo "$archive:$lib" >> "$choices_file"
  fi
done < <(find ios -mindepth 3 -maxdepth 3 -path "*/prebuilt-device/*.a" | sort)

while IFS=: read -r archive lib; do
  name="${archive#lib}"
  name="${name%.a}"

  dev="ios/$lib/prebuilt-device/$archive"
  sim="ios/$lib/prebuilt-simulator/$archive"
  headers="ios/$lib/include"

  if [ ! -f "$sim" ]; then
    echo "SKIP $lib/$archive (no simulator build found)"
    continue
  fi

  if [ -d "$headers" ]; then
    args=(-create-xcframework -library "$dev" -headers "$headers" -library "$sim" -headers "$headers")
  else
    args=(-create-xcframework -library "$dev" -library "$sim")
  fi
  args+=(-output "$OUT/$name.xcframework")

  echo "=== $name.xcframework ==="
  xcodebuild "${args[@]}"
done < "$choices_file"
