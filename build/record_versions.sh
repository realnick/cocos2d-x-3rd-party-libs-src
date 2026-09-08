#!/bin/bash
#
# Records, and checks, the 3rd party library versions this repo produces --
# for every platform, not just Windows.
#
#   build/record_versions.sh            regenerate versions.json
#   build/record_versions.sh --verify   compare against versions.json, exit 1 on drift
#
# Two different mechanisms decide versions here, and the point of the file is to
# put them side by side so divergence is visible:
#
#   vcpkg     win32 desktop and win10 UWP. The version pin is the vcpkg clone's
#             git commit, and that clone is gitignored -- so without this file
#             the Windows versions are recorded nowhere at all.
#   contrib   ios, tvos, mac, android, linux, tizen. Versions are pinned in
#             contrib/src/<library>/rules.mak and are already in the repo.
#
# Regenerating needs the vcpkg clone, so run it on the Windows machine after a
# build. --verify needs nothing but the repo, so the platforms built elsewhere
# can check whether they are in step before touching a recipe.
#
# Written in bash rather than PowerShell so it runs on the macOS and Linux
# machines that build the other platforms.

set -u

top_dir="$(cd "$(dirname "$0")/.." && pwd)"
out_file="$top_dir/versions.json"
contrib_src="$top_dir/contrib/src"
overlay_dir="$top_dir/build/vcpkg-overlay-ports"
vcpkg_dir="${COCOS_VCPKG_DIR:-$top_dir/contrib/install-win10/vcpkg}"

verify=0
[ "${1:-}" = "--verify" ] && verify=1

# --- library naming ----------------------------------------------------------
# vcpkg port names and contrib recipe directory names disagree, so both are
# mapped onto one canonical name. Without this the two halves of the table
# never line up and nothing can be compared.
canon_of_vcpkg() {
	case "$1" in
		libjpeg-turbo) echo libjpeg ;;
		tiff)          echo libtiff ;;
		glfw3)         echo glfw ;;
		sqlite3)       echo sqlite ;;
		*)             echo "$1" ;;
	esac
}

canon_of_contrib() {
	case "$1" in
		jpeg)       echo libjpeg ;;
		tiff)       echo libtiff ;;
		png)        echo libpng ;;
		webp)       echo libwebp ;;
		websockets) echo libwebsockets ;;
		uv)         echo libuv ;;
		iconv)      echo libiconv ;;
		freetype)   echo freetype ;;
		*)          echo "$1" ;;
	esac
}

# Libraries cocos2d-x names and links itself. The rest are dependencies pulled
# in by those; they still have to be deployed, but they are not what a version
# alignment discussion is about.
is_primary() {
	case "$1" in
		zlib|openssl|curl|freetype|libpng|libjpeg|libwebp|libtiff|libwebsockets|\
		libuv|libiconv|glfw|glew|chipmunk|sqlite|libogg|libvorbis|mpg123|\
		openal-soft|box2d|bullet|lua|luajit|rapidjson|glsl_optimizer) return 0 ;;
		*) return 1 ;;
	esac
}

# --- contrib side: versions out of contrib/src/<lib>/rules.mak ---------------
# Most recipes carry <NAME>_VERSION; the rest pin a git ref and a commit.
contrib_version() {
	local mak="$1" v ref sha
	v=$(sed -n 's/^[[:space:]]*[A-Z0-9_]*VERSION[[:space:]]*:\{0,1\}=[[:space:]]*\([^[:space:]]*\).*/\1/p' "$mak" | head -1)
	if [ -n "$v" ]; then
		echo "$v"
		return
	fi
	ref=$(sed -n 's/.*download_git,\$([A-Z0-9_]*),[[:space:]]*\([^,]*\),.*/\1/p' "$mak" | head -1)
	sha=$(sed -n 's/.*download_git,\$([A-Z0-9_]*),[^,]*,[[:space:]]*\([0-9a-f]*\).*/\1/p' "$mak" | head -1)
	if [ -n "$ref" ]; then
		echo "git:${ref}@${sha}"
		return
	fi
	echo ""
}

declare -A contrib_ver
if [ -d "$contrib_src" ]; then
	for d in "$contrib_src"/*/; do
		name=$(basename "$d")
		[ -f "$d/rules.mak" ] || continue
		v=$(contrib_version "$d/rules.mak")
		[ -n "$v" ] || continue
		contrib_ver["$(canon_of_contrib "$name")"]="$v"
	done
fi

# --- vcpkg side: versions out of installed/vcpkg/status ----------------------
# Stanzas start at a "Package:" line; blank lines are not reliable separators.
# A stanza carrying "Feature:" describes an installed feature, not a package.
declare -A vcpkg_ver vcpkg_triplets vcpkg_features
vcpkg_commit=""
vcpkg_date=""
vcpkg_remote=""
all_triplets=""

status_file="$vcpkg_dir/installed/vcpkg/status"
if [ -f "$status_file" ]; then
	vcpkg_commit=$(git -C "$vcpkg_dir" rev-parse HEAD 2>/dev/null || echo "")
	vcpkg_date=$(git -C "$vcpkg_dir" show -s --format=%cI HEAD 2>/dev/null || echo "")
	vcpkg_remote=$(git -C "$vcpkg_dir" remote get-url origin 2>/dev/null || echo "")

	while IFS='|' read -r kind name ver arch extra; do
		case "$kind" in
			PKG)
				canon=$(canon_of_vcpkg "$name")
				vcpkg_ver["$canon"]="$ver"
				vcpkg_triplets["$canon"]="${vcpkg_triplets[$canon]:-} $arch"
				case " $all_triplets " in *" $arch "*) ;; *) all_triplets="$all_triplets $arch" ;; esac
				;;
			FEAT)
				canon=$(canon_of_vcpkg "$name")
				key="$canon|$arch"
				vcpkg_features["$key"]="${vcpkg_features[$key]:-} $extra"
				;;
		esac
	done < <(awk '
		function flush() {
			if (pkg != "" && status == "install ok installed") {
				if (feature != "")
					printf "FEAT|%s||%s|%s\n", pkg, arch, feature
				else {
					v = version
					if (portversion != "") v = v "#" portversion
					printf "PKG|%s|%s|%s|\n", pkg, v, arch
				}
			}
			pkg=""; feature=""; version=""; portversion=""; arch=""; status=""
		}
		/^Package:/     { flush(); pkg=substr($0, 10); next }
		/^Feature:/     { feature=substr($0, 10); next }
		/^Version:/     { version=substr($0, 10); next }
		/^Port-Version:/{ portversion=substr($0, 15); next }
		/^Architecture:/{ arch=substr($0, 15); next }
		/^Status:/      { status=substr($0, 9); next }
		END { flush() }
	' "$status_file" | sed 's/[[:space:]]*$//')
fi

# --- overlay ports, whose recipes are in this repo --------------------------
declare -A overlay_ver
if [ -d "$overlay_dir" ]; then
	for d in "$overlay_dir"/*/; do
		name=$(basename "$d")
		[ -f "$d/vcpkg.json" ] || continue
		v=$(sed -n 's/.*"version\(-semver\|-string\)\{0,1\}"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\2/p' "$d/vcpkg.json" | head -1)
		pv=$(sed -n 's/.*"port-version"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$d/vcpkg.json" | head -1)
		[ -n "$pv" ] && v="$v#$pv"
		overlay_ver["$(canon_of_vcpkg "$name")"]="$v"
	done
fi

# --- combine ----------------------------------------------------------------
names=$(printf '%s\n' "${!contrib_ver[@]}" "${!vcpkg_ver[@]}" | sort -u | grep -v '^$')

# Compare only the version proper: a vcpkg port-version (#N) is a repackaging
# of the same upstream release and says nothing about which sources are used.
strip_pv() { echo "${1%%#*}"; }

n_aligned=0; n_diverged=0; n_vcpkg_only=0; n_contrib_only=0
diverged_list=""

for n in $names; do
	v_v="${vcpkg_ver[$n]:-}"
	v_c="${contrib_ver[$n]:-}"
	if [ -n "$v_v" ] && [ -n "$v_c" ]; then
		if [ "$(strip_pv "$v_v")" = "$v_c" ]; then
			n_aligned=$((n_aligned + 1))
		else
			n_diverged=$((n_diverged + 1))
			is_primary "$n" && diverged_list="$diverged_list $n"
		fi
	elif [ -n "$v_v" ]; then
		n_vcpkg_only=$((n_vcpkg_only + 1))
	else
		n_contrib_only=$((n_contrib_only + 1))
	fi
done

if [ "$verify" = "1" ]; then
	if [ ! -f "$out_file" ]; then
		echo "versions.json not found -- run $0 without --verify on the Windows machine first" >&2
		exit 1
	fi
	echo "== version alignment =="
	echo "   aligned      : $n_aligned"
	echo "   diverged     : $n_diverged"
	echo "   vcpkg only   : $n_vcpkg_only"
	echo "   contrib only : $n_contrib_only"
	if [ -n "$diverged_list" ]; then
		echo ""
		echo "-- primary libraries built at different versions --"
		for n in $diverged_list; do
			printf "    %-16s vcpkg %-12s contrib %s\n" "$n" "${vcpkg_ver[$n]}" "${contrib_ver[$n]}"
		done
		echo ""
		echo "Raising the contrib recipes is the intended direction; see the README."
		exit 1
	fi
	echo ""
	echo "== every library built on both sides is on the same version =="
	exit 0
fi

if [ -z "$vcpkg_commit" ]; then
	echo "no vcpkg clone at $vcpkg_dir -- regenerating here would drop the Windows" >&2
	echo "half of versions.json. Run this on the Windows machine, or use --verify." >&2
	exit 1
fi

# --- emit -------------------------------------------------------------------
{
	echo '{'
	echo '  "comment": "Generated by build/record_versions.sh -- do not edit. vcpkg.commit is the Windows version pin: check it out in the clone to reproduce that half exactly. The contrib half is pinned in contrib/src/<library>/rules.mak. Run record_versions.sh --verify to fail a build when the two disagree.",'
	printf '  "generated": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	echo '  "toolchains": {'
	echo '    "vcpkg": {'
	echo '      "platforms": ["win32", "win10"],'
	printf '      "remote": "%s",\n' "$vcpkg_remote"
	printf '      "commit": "%s",\n' "$vcpkg_commit"
	printf '      "commitDate": "%s",\n' "$vcpkg_date"
	echo '      "overlayPorts": "build/vcpkg-overlay-ports",'
	printf '      "triplets": ['
	sep=''
	for t in $(printf '%s\n' $all_triplets | sort); do printf '%s"%s"' "$sep" "$t"; sep=', '; done
	echo ']'
	echo '    },'
	echo '    "contrib": {'
	echo '      "platforms": ["ios", "tvos", "mac", "android", "linux", "tizen"],'
	echo '      "recipes": "contrib/src/<library>/rules.mak"'
	echo '    }'
	echo '  },'
	echo '  "summary": {'
	printf '    "aligned": %d,\n' "$n_aligned"
	printf '    "diverged": %d,\n' "$n_diverged"
	printf '    "vcpkgOnly": %d,\n' "$n_vcpkg_only"
	printf '    "contribOnly": %d\n' "$n_contrib_only"
	echo '  },'
	echo '  "libraries": {'

	first=1
	for n in $names; do
		[ "$first" = 1 ] || echo ','
		first=0
		v_v="${vcpkg_ver[$n]:-}"
		v_c="${contrib_ver[$n]:-}"
		if is_primary "$n"; then role=primary; else role=dependency; fi
		if [ -n "$v_v" ] && [ -n "$v_c" ]; then
			if [ "$(strip_pv "$v_v")" = "$v_c" ]; then state=aligned; else state=diverged; fi
		elif [ -n "$v_v" ]; then state=vcpkg-only
		else state=contrib-only
		fi

		printf '    "%s": {\n' "$n"
		printf '      "role": "%s",\n' "$role"
		printf '      "state": "%s"' "$state"

		if [ -n "$v_v" ]; then
			printf ',\n      "vcpkg": {\n'
			printf '        "version": "%s"' "$v_v"
			[ -n "${overlay_ver[$n]:-}" ] && printf ',\n        "overlayPort": true'
			printf ',\n        "triplets": ['
			sep=''
			for t in $(printf '%s\n' ${vcpkg_triplets[$n]} | sort -u); do printf '%s"%s"' "$sep" "$t"; sep=', '; done
			printf ']'
			featout=''
			for t in $(printf '%s\n' ${vcpkg_triplets[$n]} | sort -u); do
				f="${vcpkg_features[$n|$t]:-}"
				[ -n "$f" ] || continue
				fs=''
				sep2=''
				for x in $(printf '%s\n' $f | sort -u); do fs="$fs$sep2\"$x\""; sep2=', '; done
				featout="$featout$(printf '\n          "%s": [%s],' "$t" "$fs")"
			done
			if [ -n "$featout" ]; then
				printf ',\n        "features": {'
				printf '%s' "${featout%,}"
				printf '\n        }'
			fi
			printf '\n      }'
		fi

		if [ -n "$v_c" ]; then
			printf ',\n      "contrib": { "version": "%s" }' "$v_c"
		fi
		printf '\n    }'
	done
	echo ''
	echo '  }'
	echo '}'
} > "$out_file"

echo "wrote $out_file"
echo "  vcpkg commit : $vcpkg_commit ($vcpkg_date)"
echo "  libraries    : $(printf '%s\n' $names | wc -l | tr -d ' ')"
echo "  aligned $n_aligned / diverged $n_diverged / vcpkg-only $n_vcpkg_only / contrib-only $n_contrib_only"
