#!/bin/bash
#
# Installs the android / ios / mac prebuilts this repo produces into a
# cocos2d-x working tree's external/ directory -- the counterpart of
# install_to_cocos2d_x_win32.ps1 for the contrib-built platforms.
#
#   build/install_to_cocos2d_x_contrib.sh --target v3 --cocos2d-root <tree>
#   build/install_to_cocos2d_x_contrib.sh --target v4 --cocos2d-root <tree> --platforms mac
#   build/install_to_cocos2d_x_contrib.sh --target v3 --cocos2d-root <tree> --dry-run
#
# Build first: ./build.sh -p=<platform> --libs=all --arch=all for android and
# mac, and build_ios_xcframeworks.sh for ios (the trees take .xcframework
# bundles there, not fat .a files).
#
# What differs between the two targets
# ------------------------------------
#   -Target v3   external/curl/prebuilt holds libssl/libcrypto too, and libuv
#                ships inside external/websockets/prebuilt. Has tiff. No
#                separate external/openssl or external/uv on these platforms,
#                and Box2D/bullet/glsl-optimizer are built from source.
#   -Target v4   openssl and uv are their own external/ directories, and
#                Box2D, bullet and glsl-optimizer are prebuilt. No tiff.
#
# Layout written (matching what each tree already has)
#   external/<lib>/prebuilt/android/<abi>/lib<name>.a
#   external/<lib>/prebuilt/mac/lib<name>.a
#   external/<lib>/prebuilt/ios/<name>.xcframework
#   external/<lib>/include/<platform>/...
#
# Headers that are platform independent in the cocos2d-x trees (zlib, chipmunk,
# uv, Box2D, bullet, glsl-optimizer keep one include/ for every platform) are
# left alone -- installing one platform's copy over a shared directory is how
# the other platforms end up compiling against the wrong header.
#
# Every file that could not be found is listed at the end, so a partial build
# is obvious rather than silently leaving the previous version in place.

set -u

top_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$top_dir/build"
xcf_dir="$build_dir/xcframeworks"

target=""
cocos2d_root=""
platforms="android,ios,mac"
dry_run=0

usage() {
	cat >&2 <<'EOF'
usage: install_to_cocos2d_x_contrib.sh --target v3|v4 --cocos2d-root PATH [options]

  --target v3|v4          which cocos2d-x tree's layout to install for
  --cocos2d-root PATH     the tree to install into (required)
  --platforms LIST        comma separated: android,ios,mac (default: all three)
  --dry-run               print what would be copied, copy nothing
EOF
	exit 2
}

while [ $# -gt 0 ]; do
	case "$1" in
		--target)        target="${2:-}"; shift 2 ;;
		--target=*)      target="${1#*=}"; shift ;;
		--cocos2d-root)  cocos2d_root="${2:-}"; shift 2 ;;
		--cocos2d-root=*) cocos2d_root="${1#*=}"; shift ;;
		--platforms)     platforms="${2:-}"; shift 2 ;;
		--platforms=*)   platforms="${1#*=}"; shift ;;
		--dry-run)       dry_run=1; shift ;;
		-h|--help)       usage ;;
		*) echo "unknown argument: $1" >&2; usage ;;
	esac
done

case "$target" in
	v3|v4) ;;
	*) echo "--target must be v3 or v4" >&2; usage ;;
esac

[ -n "$cocos2d_root" ] || { echo "--cocos2d-root is required" >&2; usage; }

[ -d "$cocos2d_root" ] || { echo "cocos2d-x tree not found: $cocos2d_root" >&2; exit 1; }
cocos2d_root="$(cd "$cocos2d_root" && pwd)"
out_dir="$cocos2d_root/external"
[ -d "$out_dir" ] || { echo "cocos2d-x external dir not found at $out_dir" >&2; exit 1; }

missing=""
installed_count=0

note_missing() {
	missing="$missing
  $1"
	echo "warning: missing $1" >&2
}

ensure_dir() {
	[ "$dry_run" = "1" ] && return 0
	mkdir -p "$1"
}

# copy_file <src> <destdir> [destname]
copy_file() {
	local src="$1" destdir="$2" name="${3:-}"
	[ -n "$name" ] || name="$(basename "$src")"
	if [ ! -f "$src" ]; then
		note_missing "$src"
		return 1
	fi
	echo "   $src -> $destdir/$name"
	if [ "$dry_run" != "1" ]; then
		ensure_dir "$destdir"
		cp -f "$src" "$destdir/$name" || return 1
	fi
	installed_count=$((installed_count + 1))
}

# copy_dir <srcdir> <destparent> -- installs <destparent>/<basename srcdir>,
# replacing it so a header removed upstream does not linger.
copy_dir() {
	local src="$1" destparent="$2"
	if [ ! -d "$src" ]; then
		note_missing "$src (directory)"
		return 1
	fi
	local name; name="$(basename "$src")"
	echo "   $src/ -> $destparent/$name/"
	if [ "$dry_run" != "1" ]; then
		ensure_dir "$destparent"
		rm -rf "$destparent/$name"
		cp -R "$src" "$destparent/$name" || return 1
	fi
	installed_count=$((installed_count + 1))
}

# ---------------------------------------------------------------- tables ---
# One row per library: where it comes from in this repo, where it goes in the
# cocos2d-x tree, and which platforms that tree actually keeps it for.
#
#   <src>       output directory name under build/<platform>/
#   <dest>      directory under external/
#   <archives>  file names as built (also the names the trees expect)
#   <xcf>       .xcframework names for ios, or "-" when the tree has no ios dir
#   <platforms> which of android/ios/mac this row applies to
libs_for_target() {
	# src|dest|archives|xcframeworks|platforms
	cat <<'EOF'
z|zlib|libz.a|-|android,mac
png|png|libpng.a|png.xcframework|android,ios,mac
jpeg|jpeg|libjpeg.a|jpeg.xcframework|android,ios,mac
webp|webp|libwebp.a,libsharpyuv.a|webp.xcframework,sharpyuv.xcframework|android,ios,mac
freetype|freetype2|libfreetype.a|freetype.xcframework|android,ios,mac
chipmunk|chipmunk|libchipmunk.a|chipmunk.xcframework|android,ios,mac
websockets|websockets|libwebsockets.a|websockets.xcframework|android,ios,mac
glfw3|glfw3|libglfw3.a|-|mac
EOF
	if [ "$target" = "v3" ]; then
		# v3 keeps openssl beside curl and libuv beside websockets on these
		# platforms; its external/openssl and its uv have no android/ios/mac
		# directories at all.
		cat <<'EOF'
curl|curl|libcurl.a|curl.xcframework|android,ios,mac
ssl|curl|libssl.a|ssl.xcframework|android,ios,mac
crypto|curl|libcrypto.a|crypto.xcframework|android,ios,mac
uv_a|websockets|libuv_a.a|uv_a.xcframework|android,ios,mac
tiff|tiff|libtiff.a|tiff.xcframework|android,ios,mac
EOF
	else
		cat <<'EOF'
curl|curl|libcurl.a|curl.xcframework|android,ios,mac
ssl|openssl|libssl.a|ssl.xcframework|android,ios,mac
crypto|openssl|libcrypto.a|crypto.xcframework|android,ios,mac
uv_a|uv|libuv_a.a|uv_a.xcframework|android,ios,mac
box2d|Box2D|libbox2d.a|box2d.xcframework|android,ios,mac
bullet|bullet|libBulletCollision.a,libBulletDynamics.a,libBulletMultiThreaded.a,libLinearMath.a,libMiniCL.a|BulletCollision.xcframework,BulletDynamics.xcframework,BulletMultiThreaded.xcframework,LinearMath.xcframework,MiniCL.xcframework|android,ios,mac
glsl_optimizer|glsl-optimizer|libglcpp-library.a,libglsl_optimizer.a,libmesa.a|glcpp-library.xcframework,glsl_optimizer.xcframework,mesa.xcframework|ios,mac
EOF
	fi
}

# Headers, which the trees keep per platform under include/<platform>/.
#
#   dir:<name>     copy that directory out of the built include/ tree
#   files:a.h,b.h  copy those files flat (paths are relative to include/)
#
# Libraries whose cocos2d-x include/ directory is shared by every platform
# (zlib, chipmunk, uv, Box2D, bullet, glsl-optimizer) are deliberately absent:
# writing one platform's headers there would misconfigure the others.
headers_for_target() {
	# src|dest|spec|platforms
	cat <<'EOF'
curl|curl|dir:curl|android,ios,mac
freetype|freetype2|dir:freetype2|android,ios,mac
png|png|files:png.h,pngconf.h,pnglibconf.h|android,ios,mac
jpeg|jpeg|files:jconfig.h,jerror.h,jmorecfg.h,jpeglib.h|android,ios,mac
webp|webp|files:webp/decode.h,webp/encode.h,webp/types.h|android,ios,mac
websockets|websockets|files:libwebsockets.h,lws_config.h|android,ios,mac
websockets|websockets|dir:libwebsockets|android,ios,mac
glfw3|glfw3|files:GLFW/glfw3.h,GLFW/glfw3native.h|mac
EOF
	if [ "$target" = "v3" ]; then
		cat <<'EOF'
tiff|tiff|files:tiff.h,tiffconf.h,tiffio.h,tiffvers.h|android,ios,mac
EOF
	else
		cat <<'EOF'
ssl|openssl|dir:openssl|android,ios,mac
EOF
	fi
}

in_list() { # needle list
	case ",$2," in *",$1,"*) return 0 ;; esac
	return 1
}

# Where a platform's built headers live. ios headers come from the device
# build; they are identical across the ios arch sets.
include_root() { # platform src
	echo "$build_dir/$1/$2/include"
}

# --------------------------------------------------------------- install ---
install_headers() { # platform
	local platform="$1" line src dest spec plats root
	echo "-- $platform headers --"
	while IFS='|' read -r src dest spec plats; do
		[ -n "$src" ] || continue
		in_list "$platform" "$plats" || continue
		root="$(include_root "$platform" "$src")"
		if [ ! -d "$root" ]; then
			note_missing "$root (nothing built for $src on $platform)"
			continue
		fi
		case "$spec" in
			dir:*)
				copy_dir "$root/${spec#dir:}" "$out_dir/$dest/include/$platform"
				;;
			files:*)
				local files="${spec#files:}" f
				for f in $(echo "$files" | tr ',' ' '); do
					copy_file "$root/$f" "$out_dir/$dest/include/$platform"
				done
				;;
		esac
	done < <(headers_for_target)
}

install_android() {
	local line src dest archives xcf plats abi a
	echo "-- android --"
	while IFS='|' read -r src dest archives xcf plats; do
		[ -n "$src" ] || continue
		in_list android "$plats" || continue
		for abi in armeabi-v7a arm64-v8a x86 x86_64; do
			[ -d "$build_dir/android/$src/prebuilt/$abi" ] || continue
			for a in $(echo "$archives" | tr ',' ' '); do
				copy_file "$build_dir/android/$src/prebuilt/$abi/$a" \
					"$out_dir/$dest/prebuilt/android/$abi"
			done
		done
	done < <(libs_for_target)
}

install_mac() {
	local src dest archives xcf plats a
	echo "-- mac --"
	while IFS='|' read -r src dest archives xcf plats; do
		[ -n "$src" ] || continue
		in_list mac "$plats" || continue
		for a in $(echo "$archives" | tr ',' ' '); do
			copy_file "$build_dir/mac/$src/prebuilt/$a" "$out_dir/$dest/prebuilt/mac"
		done
	done < <(libs_for_target)
}

install_ios() {
	local src dest archives xcf plats f
	echo "-- ios --"
	while IFS='|' read -r src dest archives xcf plats; do
		[ -n "$src" ] || continue
		in_list ios "$plats" || continue
		[ "$xcf" = "-" ] && continue
		for f in $(echo "$xcf" | tr ',' ' '); do
			copy_dir "$xcf_dir/$f" "$out_dir/$dest/prebuilt/ios"
		done
	done < <(libs_for_target)
}

# ------------------------------------------------------------------ main ---
echo "== installing cocos2d-x $target deps (android / ios / mac) =="
echo "   source: $build_dir"
echo "   target: $out_dir"
echo "   platforms: $platforms"
[ "$dry_run" = "1" ] && echo "   (dry run -- nothing is copied)"
echo ""

did_any=0
for platform in $(echo "$platforms" | tr ',' ' '); do
	case "$platform" in
		android|ios|mac) ;;
		*) echo "unknown platform, skipping: $platform" >&2; continue ;;
	esac
	if [ "$platform" = "ios" ]; then
		if [ ! -d "$xcf_dir" ]; then
			echo "warning: no $xcf_dir -- run build_ios_xcframeworks.sh first; skipping ios" >&2
			continue
		fi
		# The xcframeworks are packaged by a separate script, so they can easily
		# predate a recipe bump that android and mac have already picked up --
		# which would quietly leave one platform on the old library version.
		newest_recipe="$(find "$top_dir/contrib/src" -name 'rules.mak' -o -name 'SHA512SUMS' | xargs ls -t 2>/dev/null | head -1)"
		if [ -n "$newest_recipe" ] && [ "$newest_recipe" -nt "$xcf_dir" ]; then
			echo "warning: $xcf_dir is older than $(basename "$(dirname "$newest_recipe")")'s recipe --" >&2
			echo "         these xcframeworks predate a version bump. Re-run build_ios_xcframeworks.sh" >&2
			echo "         or the ios prebuilts will be a different version than android and mac." >&2
		fi
	elif [ ! -d "$build_dir/$platform" ]; then
		echo "warning: nothing built for $platform (no $build_dir/$platform); skipping" >&2
		continue
	fi

	install_headers "$platform"
	case "$platform" in
		android) install_android ;;
		mac)     install_mac ;;
		ios)     install_ios ;;
	esac
	did_any=1
	echo ""
done

[ "$did_any" = "1" ] || { echo "nothing installed -- build first" >&2; exit 1; }

if [ -n "$missing" ]; then
	echo "-- not found (nothing was installed for these) --"
	printf '%s\n' "$missing" | sed '/^$/d' | sort -u
	echo ""
fi

echo "== $target deps installed under $out_dir =="
echo ""
echo "Next on the cocos2d-x side:"
echo "  - link libsharpyuv.a next to libwebp.a: recent libwebp splits the sharp"
echo "    YUV conversion into its own archive (Android.mk / CMakeLists / xcodeproj)"
echo "  - openssl is 3.x now, as it already is on Windows. Anything still calling"
echo "    1.1.1-era APIs has to move with it"
echo "  - libwebsockets is 4.x: its libwebsockets.h pulls in the libwebsockets/"
echo "    directory that now ships beside it, and the lws 2.x API it replaces is"
echo "    not source compatible"
if [ "$target" = "v3" ]; then
	echo "  - v3 keeps libssl/libcrypto under external/curl/prebuilt and libuv_a"
	echo "    under external/websockets/prebuilt; that is where they were installed"
fi
