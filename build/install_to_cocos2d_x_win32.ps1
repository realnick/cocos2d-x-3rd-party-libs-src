#Requires -Version 5.0
<#
Installs the Windows *desktop* dependencies built by build_win32_desktop.bat
into a cocos2d-x working tree's external\ directory.

build_win32_desktop.bat builds the union of what cocos2d-x v3 and v4 need;
this script picks the subset, the linkage and the file names for one of them:

  -Target v4   the CMake-based tree (external\cmake\CocosExternalConfig.cmake)
               curl openssl freetype png jpeg webp glfw3 uv websockets(DLL)
               chipmunk + win32-specific ogg/vorbis mpg123 openal glew iconv zlib
  -Target v3   the vcxproj-based tree (cocos\2d\libcocos2d.vcxproj xcopies
               external\<lib>\prebuilt\<arch>\ into $(OutDir))
               curl freetype png jpeg webp tiff glfw3 websockets(static) sqlite3
               chipmunk + the same win32-specific set.  No openssl, no uv.

Layout (both targets)
---------------------
  <lib>\prebuilt\<arch>              arch is win32 | win64 | arm64
  sqlite3\libraries\<arch>           (v3 only, matching its existing layout)
  win32-specific\<lib>\prebuilt      flat for win32, \<arch> for the others,
                                     because cocos2d-x has it flat today
  <lib>\include\win32                headers, architecture independent

win32 lands exactly where both trees already look, so an existing 32-bit build
keeps working untouched. win64 and arm64 are new sibling directories: v4 needs
CocosExternalConfig.cmake to choose platform_spec_path by architecture, and v3
needs x64/ARM64 platform configurations whose xcopy steps point at the matching
prebuilt\<arch> directory.

File names: vcpkg's modern outputs do not always match the names cocos2d-x
hardcodes. Static libs and import libs are installed under the cocos2d-x name;
a DLL keeps the name burned into its import library, so those the engine side
has to follow. Every rename and every missing file is listed at the end.
#>
param(
    [Parameter(Mandatory=$true)][ValidateSet('v3','v4')][string]$Target,

    # Root of the target cocos2d-x working tree (the directory holding external\).
    [Parameter(Mandatory=$true)][string]$Cocos2dRoot,

    [string[]]$Arches = @('win32','win64','arm64'),

    # vcpkg clone used by build_win32_desktop.bat. Defaults to the one shared
    # with build_win10_uwp.bat, or to COCOS_VCPKG_DIR when that is set.
    [string]$VcpkgDir = ""
)

$ErrorActionPreference = 'Stop'

if (-not $VcpkgDir) { $VcpkgDir = $env:COCOS_VCPKG_DIR }
if (-not $VcpkgDir) {
    # Must match build_win32_desktop.bat. The path is under install-win10 for
    # historical reasons only; that single clone serves UWP and desktop alike,
    # which is what keeps their library versions identical.
    $VcpkgDir = Join-Path $PSScriptRoot '..\contrib\install-win10\vcpkg'
}

$OutDir = Join-Path $Cocos2dRoot 'external'
if (-not (Test-Path -LiteralPath $OutDir)) {
    throw "cocos2d-x external dir not found at $OutDir"
}

$script:Missing = @()
$script:Renamed = @()

function Ensure-Dir([string]$dir) {
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# Copies the first of $names that exists in $srcDir. $As renames the copy,
# which is only ever used for static libs and import libs -- never for a DLL,
# whose name is recorded inside the import library.
function Copy-First([string]$srcDir, [string[]]$names, [string]$destDir, [string]$As = "", [switch]$Optional) {
    foreach ($n in $names) {
        $src = Join-Path $srcDir $n
        if (Test-Path -LiteralPath $src) {
            Ensure-Dir $destDir
            $destName = $n
            if ($As) { $destName = $As }
            Copy-Item -LiteralPath $src -Destination (Join-Path $destDir $destName) -Force
            if ($As -and ($As -ne $n)) {
                $script:Renamed += "  $n  ->  $destName"
            }
            return
        }
    }
    if (-not $Optional) {
        $script:Missing += "  $($names -join ' | ')   (in $srcDir)"
        Write-Warning "missing: $($names -join ' | ') in $srcDir"
    }
}

# Copies every file matching $pattern; used where the exact name carries a
# version or an architecture (libcrypto-3-x64.dll and friends).
function Copy-Glob([string]$srcDir, [string]$pattern, [string]$destDir, [switch]$Optional) {
    $hits = @(Get-ChildItem -LiteralPath $srcDir -Filter $pattern -File -ErrorAction SilentlyContinue)
    if ($hits.Count -eq 0) {
        if (-not $Optional) {
            $script:Missing += "  $pattern   (in $srcDir)"
            Write-Warning "missing: $pattern in $srcDir"
        }
        return
    }
    Ensure-Dir $destDir
    foreach ($h in $hits) { Copy-Item -LiteralPath $h.FullName -Destination $destDir -Force }
}

function Copy-Tree([string]$src, [string]$destDir) {
    if (-not (Test-Path -LiteralPath $src)) {
        $script:Missing += "  $src   (tree)"
        Write-Warning "missing tree: $src"
        return
    }
    Ensure-Dir $destDir
    Copy-Item -LiteralPath $src -Destination $destDir -Recurse -Force
}

# vcpkg's shared zlib installs a zconf.h whose `#ifdef ZLIB_DLL` guard has been
# rewritten to `#if 1`, so ZEXTERN is unconditionally `extern __declspec(dllimport)`.
# That is right for zlib's own API, but cocos2d-x's external\unzip\unzip.h declares
# *its own* functions with ZEXTERN/ZEXPORT, and unzip.cpp then fails to define them:
#
#   unzip.cpp(509): error C2491: 'cocos2d::unzOpen2': definition of dllimport
#                   function not allowed
#
# cocos2d-x's own bundled zconf.h has the `#ifdef ZLIB_DLL` form, which is why this
# used to build, so restore it. zlib's functions lose the dllimport hint and are
# called through a thunk instead -- a negligible cost, and they still resolve
# through the import library.
function Repair-ZConfDllGuard([string]$zconf) {
    if (-not (Test-Path -LiteralPath $zconf)) { return }
    $text = [System.IO.File]::ReadAllText($zconf)
    # The `#  if 1` that follows is the one guarding zlib's dllimport ZEXTERN;
    # the file has a second `#  if 1` under __BEOS__, whose next line differs,
    # so keying off the following line picks out the right one. \r?\n keeps the
    # file's CRLF endings intact.
    $pattern     = '(?m)^#  if 1(\r?\n)(#    if defined\(WIN32\))'
    $replacement = '#  ifdef ZLIB_DLL$1$2'
    if ($text -match $pattern) {
        [System.IO.File]::WriteAllText($zconf, [regex]::Replace($text, $pattern, $replacement))
        $script:Renamed += "  zconf.h: restored the #ifdef ZLIB_DLL guard (was #if 1)"
    } elseif ($text -notmatch '(?m)^#  ifdef ZLIB_DLL') {
        $script:Missing += "  zconf.h: could not find the ZLIB_DLL guard to restore -- check external\unzip still builds"
        Write-Warning "zconf.h: ZLIB_DLL guard not in the expected form; external\unzip may hit C2491"
    }
}

# A few headers are generated per architecture, but cocos2d-x has one
# include\win32 tree that every architecture compiles against:
#
#   openssl\configuration.h   BN_LLONG / THIRTY_TWO_BIT vs SIXTY_FOUR_BIT, and
#                             RC4_INT (unsigned char on arm64, unsigned int
#                             elsewhere) -- so BN_ULONG and RC4_KEY change width
#   tiffconf.h                TIFF_SSIZE_T is int32_t or int64_t, which is the
#                             return type of TIFFReadEncodedStrip and friends
#
# Shipping one architecture's copy makes the other two disagree with their own
# prebuilt libraries. It goes unnoticed while callers only pass opaque pointers
# around, and corrupts arguments the moment one of these types is used.
#
# So install the real headers side by side under canonical architecture names
# and leave a dispatching stub where the original was. A branch whose header was
# never installed simply fails to open, which is the error you want.
function Install-ArchHeader([string]$srcFile, [string]$destDir, [string]$baseName, [string]$canonicalArch) {
    if (-not (Test-Path -LiteralPath $srcFile)) {
        $script:Missing += "  $baseName.h   (in $(Split-Path $srcFile -Parent))"
        Write-Warning "missing: $srcFile"
        return
    }
    Ensure-Dir $destDir
    Copy-Item -LiteralPath $srcFile -Destination (Join-Path $destDir "$baseName-$canonicalArch.h") -Force

    $stub = @"
/*
 * Generated by install_to_cocos2d_x_win32.ps1 -- do not edit.
 *
 * $baseName.h is configured per architecture, but cocos2d-x keeps a single
 * include tree for all of them, so the real headers sit next to this one and
 * this picks the matching one at compile time.
 */
#if defined(_M_ARM64) || defined(__aarch64__)
#  include "$baseName-arm64.h"
#elif defined(_M_X64) || defined(_M_AMD64) || defined(__x86_64__)
#  include "$baseName-x64.h"
#elif defined(_M_IX86) || defined(__i386__)
#  include "$baseName-x86.h"
#else
#  error "$baseName.h: unsupported architecture"
#endif
"@
    [System.IO.File]::WriteAllText((Join-Path $destDir "$baseName.h"), $stub)
    $script:Renamed += "  $baseName.h -> $baseName-$canonicalArch.h plus a per-arch dispatching stub"
}

function Get-TripletBase([string]$arch) {
    switch ($arch.ToLower()) {
        'win32' { 'x86' }
        'x86'   { 'x86' }
        'win64' { 'x64' }
        'x64'   { 'x64' }
        'arm64' { 'arm64' }
        default { $null }
    }
}

# ---------------------------------------------------------------- headers ---
# Written once; they are the same for every architecture.
function Install-Headers([string]$dynInc, [string]$stInc) {
    Write-Host "-- headers --"

    Copy-Tree "$dynInc\curl" "$OutDir\curl\include\win32\"

    Copy-Tree "$stInc\freetype" "$OutDir\freetype2\include\win32\freetype2\"
    Copy-First $stInc @('ft2build.h') "$OutDir\freetype2\include\win32\freetype2"

    foreach ($h in @('png.h','pngconf.h','pnglibconf.h')) {
        Copy-First $stInc @($h) "$OutDir\png\include\win32"
    }
    foreach ($h in @('jpeglib.h','jconfig.h','jmorecfg.h','jerror.h')) {
        Copy-First $stInc @($h) "$OutDir\jpeg\include\win32"
    }
    # cocos2d-x expects the webp headers flat; vcpkg ships them under include\webp.
    foreach ($h in @('decode.h','encode.h','types.h','mux_types.h','demux.h')) {
        Copy-First "$stInc\webp" @($h) "$OutDir\webp\include\win32"
    }
    foreach ($h in @('glfw3.h','glfw3native.h')) {
        Copy-First "$stInc\GLFW" @($h) "$OutDir\glfw3\include\win32"
    }

    # libwebsockets ships several headers at the top of include/. v3 links the
    # static build, so its headers come from the static tree.
    $lwsInc = $dynInc
    if ($Target -eq 'v3') { $lwsInc = $stInc }
    $lwsHeaders = @(Get-ChildItem -LiteralPath $lwsInc -Filter 'libwebsockets*' -ErrorAction SilentlyContinue)
    if ($lwsHeaders.Count -gt 0) { Ensure-Dir "$OutDir\websockets\include\win32" }
    foreach ($h in $lwsHeaders) {
        Copy-Item -LiteralPath $h.FullName -Destination "$OutDir\websockets\include\win32\" -Recurse -Force
    }
    Copy-First $lwsInc @('lws_config.h')      "$OutDir\websockets\include\win32"
    Copy-First $lwsInc @('lws_config_priv.h') "$OutDir\websockets\include\win32" -Optional

    Copy-Tree "$dynInc\ogg"    "$OutDir\win32-specific\OggDecoder\include\"
    Copy-Tree "$dynInc\vorbis" "$OutDir\win32-specific\OggDecoder\include\"
    foreach ($h in @('mpg123.h','fmt123.h')) {
        Copy-First $dynInc @($h) "$OutDir\win32-specific\MP3Decoder\include"
    }
    Copy-Tree "$dynInc\AL" "$OutDir\win32-specific\OpenalSoft\include\"
    Copy-Tree "$dynInc\GL" "$OutDir\win32-specific\gles\include\OGLES\"
    Copy-First $dynInc @('iconv.h') "$OutDir\win32-specific\icon\include"
    foreach ($h in @('zlib.h','zconf.h')) {
        Copy-First $dynInc @($h) "$OutDir\win32-specific\zlib\include"
    }
    Repair-ZConfDllGuard "$OutDir\win32-specific\zlib\include\zconf.h"

    # openssl headers are the same in both trees; take them from the tree whose
    # linkage that target actually uses.
    if ($Target -eq 'v4') {
        Copy-Tree "$dynInc\openssl" "$OutDir\openssl\include\win32\"
    } else {
        Copy-Tree "$stInc\openssl" "$OutDir\openssl\include\win32\"
    }
    if ($Target -eq 'v3') {
        foreach ($h in @('tiff.h','tiffconf.h','tiffio.h','tiffvers.h')) {
            # From the static tree: tiffconf.h records which codecs the library
            # was built with, and the [core] build has no JPEG/ZIP/LZMA support.
            Copy-First $stInc @($h) "$OutDir\tiff\include\win32"
        }
        Copy-First $dynInc @('sqlite3.h','sqlite3ext.h') "$OutDir\sqlite3\include"
    }
}

# ------------------------------------------------------------ binaries ------
function Install-Arch([string]$arch, [string]$dyn, [string]$st) {
    $dynBin   = Join-Path $dyn 'bin'
    $dynLib   = Join-Path $dyn 'lib'
    $dynInc   = Join-Path $dyn 'include'
    $stLib    = Join-Path $st  'lib'
    $stDbgLib = Join-Path $st  'debug\lib'
    $stInc    = Join-Path $st  'include'
    $canon    = Get-TripletBase $arch

    # win32-specific\<lib>\prebuilt is flat in cocos2d-x; keep it that way for
    # the 32-bit build and give the new architectures a subdirectory.
    $specSub = ""
    if ($arch -ne 'win32') { $specSub = "\$arch" }

    $curl     = "$OutDir\curl\prebuilt\$arch"
    $freetype = "$OutDir\freetype2\prebuilt\$arch"
    $png      = "$OutDir\png\prebuilt\$arch"
    $jpeg     = "$OutDir\jpeg\prebuilt\$arch"
    $webp     = "$OutDir\webp\prebuilt\$arch"
    $glfw     = "$OutDir\glfw3\prebuilt\$arch"
    $ws       = "$OutDir\websockets\prebuilt\$arch"
    $chip     = "$OutDir\chipmunk\prebuilt\$arch"
    $ogg      = "$OutDir\win32-specific\OggDecoder\prebuilt$specSub"
    $mp3      = "$OutDir\win32-specific\MP3Decoder\prebuilt$specSub"
    $openal   = "$OutDir\win32-specific\OpenalSoft\prebuilt$specSub"
    $gles     = "$OutDir\win32-specific\gles\prebuilt$specSub"
    $iconv    = "$OutDir\win32-specific\icon\prebuilt$specSub"
    $zlib     = "$OutDir\win32-specific\zlib\prebuilt$specSub"

    # --- shared by v3 and v4 ---

    # curl (names already match cocos2d-x)
    Copy-First $dynBin @('libcurl.dll') $curl
    Copy-First $dynLib @('libcurl.lib') $curl

    # freetype (static, built as freetype[core] so it drags in no png/zlib/brotli)
    Copy-First $stLib @('freetype.lib') $freetype

    # png / jpeg / webp / glfw3 (static; renamed to the cocos2d-x names)
    Copy-First $stLib @('libpng16.lib','png16.lib','libpng.lib') $png  'libpng.lib'
    Copy-First $stLib @('jpeg.lib','libjpeg.lib')                $jpeg 'libjpeg.lib'
    Copy-First $stLib @('webp.lib','libwebp.lib')                $webp 'libwebp.lib'
    # Recent libwebp splits the sharp YUV conversion out; cocos2d-x links only
    # libwebp.lib, so this one has to be added on the engine side.
    Copy-First $stLib @('sharpyuv.lib','libsharpyuv.lib')        $webp 'libsharpyuv.lib' -Optional
    Copy-First $stLib @('glfw3.lib')                             $glfw

    # chipmunk (static, and the only lib cocos2d-x wants in debug *and* release).
    # The overlay port pins 7.0.1 with CP_USE_DOUBLES=0, which is what both the
    # v3 and the v4 trees bundle headers for.
    Copy-First $stLib    @('chipmunk.lib')                 "$chip\release-lib" 'libchipmunk.lib'
    Copy-First $stDbgLib @('chipmunk.lib','chipmunkd.lib') "$chip\debug-lib"   'libchipmunk.lib'

    # libogg / libvorbis -- cocos2d-x expects the lib* DLL names, vcpkg drops
    # the prefix. The import libs are renamed; the DLLs cannot be.
    Copy-First $dynBin @('ogg.dll','libogg.dll')               $ogg
    Copy-First $dynLib @('ogg.lib','libogg.lib')               $ogg 'libogg.lib'
    Copy-First $dynBin @('vorbis.dll','libvorbis.dll')         $ogg
    Copy-First $dynLib @('vorbis.lib','libvorbis.lib')         $ogg 'libvorbis.lib'
    Copy-First $dynBin @('vorbisfile.dll','libvorbisfile.dll') $ogg
    Copy-First $dynLib @('vorbisfile.lib','libvorbisfile.lib') $ogg 'libvorbisfile.lib'
    Copy-First $dynBin @('vorbisenc.dll','libvorbisenc.dll')   $ogg -Optional
    Copy-First $dynLib @('vorbisenc.lib','libvorbisenc.lib')   $ogg 'libvorbisenc.lib' -Optional

    # mpg123 / openal-soft / glew / libiconv / zlib
    Copy-First $dynBin @('mpg123.dll','libmpg123.dll') $mp3
    Copy-First $dynLib @('mpg123.lib','libmpg123.lib') $mp3 'libmpg123.lib'
    Copy-First $dynBin @('OpenAL32.dll','openal.dll')  $openal
    Copy-First $dynLib @('OpenAL32.lib','openal.lib')  $openal 'OpenAL32.lib'
    # Current openal-soft links fmt dynamically, so OpenAL32.dll will not load
    # without it. Nothing links fmt directly -- it only has to be deployed.
    Copy-First $dynBin @('fmt.dll')                    $openal
    Copy-First $dynBin @('glew32.dll')                 $gles
    Copy-First $dynLib @('glew32.lib')                 $gles
    Copy-First $dynBin @('iconv-2.dll','iconv.dll')    $iconv
    Copy-First $dynBin @('charset-1.dll')              $iconv -Optional
    Copy-First $dynLib @('iconv.lib','libiconv.lib')   $iconv 'libiconv.lib'
    Copy-First $dynLib @('charset.lib')                $iconv -Optional
    Copy-First $dynBin @('zlib1.dll','z.dll')          $zlib
    Copy-First $dynLib @('zlib.lib','z.lib')           $zlib 'libzlib.lib'

    if ($Target -eq 'v4') {
        # openssl -- vcpkg ships 3.x, whose DLLs carry a version + arch suffix
        # (libcrypto-3-x64.dll). cocos2d-x hardcodes the 1.1 names, so the
        # engine side has to be updated; the import libs keep their names.
        $openssl = "$OutDir\openssl\prebuilt\$arch"
        Copy-Glob  $dynBin 'libcrypto-*.dll'  $openssl
        Copy-Glob  $dynBin 'libssl-*.dll'     $openssl
        Copy-First $dynBin @('legacy.dll')    $openssl -Optional
        Copy-First $dynLib @('libcrypto.lib') $openssl
        Copy-First $dynLib @('libssl.lib')    $openssl

        Install-ArchHeader "$dynInc\openssl\configuration.h" `
            "$OutDir\openssl\include\win32\openssl" 'configuration' $canon

        # libuv (cocos2d-x links the import lib under the name uv_a.lib)
        $uv = "$OutDir\uv\prebuilt\$arch"
        Copy-First $dynBin @('uv.dll','libuv.dll') $uv
        Copy-First $dynLib @('uv.lib','libuv.lib') $uv 'uv_a.lib'

        # libwebsockets, shared (+ pthreads runtime; websockets links pthreads)
        Copy-First $dynBin @('websockets.dll') $ws
        Copy-First $dynLib @('websockets.lib') $ws
        Copy-First $dynBin @('pthreadVC3.dll') $ws -Optional
        Copy-First $dynLib @('pthreadVC3.lib') $ws -Optional
    }

    if ($Target -eq 'v3') {
        # libwebsockets, static -- v3 has no websockets.dll in its prebuilts.
        Copy-First $stLib @('websockets.lib','websockets_static.lib') $ws 'websockets.lib'

        # openssl, static (the static-md tree has no DLLs, so nothing to deploy).
        #
        # v3's own prebuilt websockets.lib was self-contained: openssl was
        # merged into the archive, which is why external\openssl has no win32
        # headers and an empty prebuilt\win32 to this day. vcpkg's static
        # websockets.lib is not -- it leaves ~273 openssl symbols undefined --
        # so the engine has to link libssl.lib and libcrypto.lib alongside it.
        $openssl = "$OutDir\openssl\prebuilt\$arch"
        Copy-First $stLib @('libssl.lib')    $openssl
        Copy-First $stLib @('libcrypto.lib') $openssl

        Install-ArchHeader "$stInc\openssl\configuration.h" `
            "$OutDir\openssl\include\win32\openssl" 'configuration' $canon

        # tiff, static and self-contained.
        #
        # v3 links libtiff into libcocos2d and its xcopy step only takes *.lib
        # from tiff\prebuilt, so a shared build would never get its DLL
        # deployed. The shared vcpkg build also drags in jpeg62.dll and
        # liblzma.dll, which cocos2d-x has nowhere to put. tiff[core] drops
        # jpeg, lzma and zip and matches what contrib\src\tiff\rules.mak has
        # always produced for the other platforms.
        $tiff = "$OutDir\tiff\prebuilt\$arch"
        Copy-First $stLib @('tiff.lib','libtiff.lib') $tiff 'libtiff.lib'

        Install-ArchHeader "$stInc\tiffconf.h" `
            "$OutDir\tiff\include\win32" 'tiffconf' $canon

        # sqlite3 (v3 keeps it under libraries\, not prebuilt\)
        $sqlite = "$OutDir\sqlite3\libraries\$arch"
        Copy-First $dynBin @('sqlite3.dll') $sqlite
        Copy-First $dynLib @('sqlite3.lib') $sqlite
    }
}

# ------------------------------------------------------------------ main ---
Write-Host "== installing cocos2d-x $Target deps (win32 desktop) =="
Write-Host "   vcpkg:  $VcpkgDir"
Write-Host "   target: $OutDir"
Write-Host "   arches: $($Arches -join ', ')"
Write-Host ""

$headersDone = $false
$installed = @()

foreach ($arch in $Arches) {
    $base = Get-TripletBase $arch
    if (-not $base) {
        Write-Warning "unknown architecture, skipping: $arch"
        continue
    }
    $dyn = Join-Path $VcpkgDir "installed\$base-windows"
    $st  = Join-Path $VcpkgDir "installed\$base-windows-static-md"
    if (-not (Test-Path -LiteralPath $dyn) -or -not (Test-Path -LiteralPath $st)) {
        Write-Warning "not built yet, skipping $arch (looked for $dyn and $st) -- run build_win32_desktop.bat $arch"
        continue
    }

    if (-not $headersDone) {
        Install-Headers (Join-Path $dyn 'include') (Join-Path $st 'include')
        $headersDone = $true
        Write-Host ""
    }

    Write-Host "-- $arch --"
    Install-Arch $arch $dyn $st
    $installed += $arch
    Write-Host ""
}

if ($installed.Count -eq 0) {
    throw "nothing installed -- run build_win32_desktop.bat first"
}

if ($script:Renamed.Count -gt 0) {
    Write-Host "-- installed under a cocos2d-x name --"
    $script:Renamed | Sort-Object -Unique | ForEach-Object { Write-Host $_ }
    Write-Host ""
}
if ($script:Missing.Count -gt 0) {
    Write-Host "-- not found in the vcpkg trees --"
    $script:Missing | Sort-Object -Unique | ForEach-Object { Write-Host $_ }
    Write-Host ""
}

Write-Host "== $Target deps installed under $OutDir for: $($installed -join ', ') =="
Write-Host ""
if ($Target -eq 'v4') {
    Write-Host "Next on the cocos2d-x side:"
    Write-Host "  - external\cmake\CocosExternalConfig.cmake: choose platform_spec_path"
    Write-Host "    by architecture instead of hardcoding win32"
    Write-Host "  - external\openssl\CMakeLists.txt: openssl 3.x DLL names"
    Write-Host "    (libcrypto-3-<arch>.dll, not libcrypto-1_1.dll)"
    Write-Host "  - external\win32-specific\OggDecoder\CMakeLists.txt: ogg.dll /"
    Write-Host "    vorbis.dll / vorbisfile.dll, not the lib* names"
    Write-Host "  - external\zlib\CMakeLists.txt: the zlib DLL is z.dll, not zlib1.dll"
    Write-Host "  - external\webp\CMakeLists.txt: link libsharpyuv.lib too"
    Write-Host "  - external\win32-specific\OpenalSoft\CMakeLists.txt: OpenAL32.dll"
    Write-Host "    now needs fmt.dll beside it. Only IMPORTED_LOCATION entries get"
    Write-Host "    deployed, so APPEND fmt.dll to it the way OggDecoder already"
    Write-Host "    does for its extra DLLs."
} else {
    Write-Host "Next on the cocos2d-x side:"
    Write-Host "  - cocos\2d\libcocos2d.vcxproj: link libssl.lib and libcrypto.lib"
    Write-Host "    next to websockets.lib, and xcopy external\openssl\prebuilt\<arch>."
    Write-Host "    v3's own websockets.lib had openssl merged in; vcpkg's does not."
    Write-Host "  - cocos\2d\libcocos2d.vcxproj: add x64 / ARM64 platform"
    Write-Host "    configurations whose xcopy steps read prebuilt\<arch>\"
    Write-Host "    instead of prebuilt\win32\"
    Write-Host "  - win32-specific xcopy steps read prebuilt\<arch>\ for the"
    Write-Host "    new architectures and stay flat for win32"
    Write-Host "  - the ogg/vorbis, iconv and zlib DLLs are named ogg.dll /"
    Write-Host "    vorbis.dll / vorbisfile.dll / iconv-2.dll / z.dll, not the"
    Write-Host "    lib* names -- the xcopy steps deploy them by wildcard, but"
    Write-Host "    anything naming them explicitly has to follow"
}
