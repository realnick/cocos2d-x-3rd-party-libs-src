#Requires -Version 5.0
<#
Installs the UWP prebuilt binaries produced by build_win10_uwp.bat into a
cocos2d-x working tree's external/ directory.

  powershell -File install_to_cocos2d_x_uwp.ps1 -DepsRoot <this repo> -Cocos2dRoot <v3 tree>
  powershell -File install_to_cocos2d_x_uwp.ps1 ... -Arches x64
  powershell -File install_to_cocos2d_x_uwp.ps1 ... -SkipHeaders

Architecture tokens are win32, x64 and arm64, matching cocos2d-x's
prebuilt\win10\<arch> directories; all three are installed by default.
The UWP path targets cocos2d-x v3 only.

Headers are installed too, because the libraries and the headers have to come
from the same vcpkg versions -- linking libwebsockets 4.5.8 against the
libwebsockets 2.x headers cocos2d-x used to ship would not be safe. They are
merged into the existing include directories rather than replacing them, so
cocos2d-x's own files there (private-libwebsockets.h and the like) survive.
Pass -SkipHeaders to install binaries only.

Per-arch binary directories *are* replaced wholesale, so a stale file from an
older build cannot linger. Other architectures are left untouched.
#>
param(
    # Root of this repo (cocos2d-x-3rd-party-libs-src).
    [Parameter(Mandatory=$true)][string]$DepsRoot,

    # Root of the target cocos2d-x working tree.
    [Parameter(Mandatory=$true)][string]$Cocos2dRoot,

    [string[]]$Arches = @('win32','x64','arm64'),

    [switch]$SkipHeaders
)

$ErrorActionPreference = 'Stop'

$src = Join-Path $DepsRoot 'contrib\install-win10\external\cocos2d-x-deps'
if (-not (Test-Path -LiteralPath $src)) {
    throw "cocos2d-x-deps not built yet at $src -- run build_win10_uwp.bat first"
}

$dst = Join-Path $Cocos2dRoot 'external'
if (-not (Test-Path -LiteralPath $dst)) {
    throw "cocos2d-x external dir not found at $dst"
}

Write-Host "== installing cocos2d-x UWP deps =="
Write-Host "   from:   $src"
Write-Host "   to:     $dst"
Write-Host "   arches: $($Arches -join ', ')"
Write-Host ""

# Architecture independent; merged in so cocos2d-x's own headers survive.
$HeaderDirs = @(
    "curl\include\win10",
    "openssl\include\win10",
    "freetype2\include\win10",
    "websockets\include\win10",
    "win10-specific\OggDecoder\include",
    "win10-specific\zlib\include",
    "win10-specific\angle\include"
)

# Per architecture; replaced wholesale. Every path ends at the <arch> level so
# the directory can be copied as a unit.
function Get-ArchDirs([string]$arch) {
    @(
        "curl\prebuilt\win10\$arch",
        "openssl\prebuilt\win10\$arch",
        "freetype2\prebuilt\win10\$arch",
        "sqlite3\libraries\win10\$arch",
        "websockets\prebuilt\win10\$arch",
        "chipmunk\prebuilt\win10\$arch",
        "win10-specific\OggDecoder\prebuilt\$arch",
        "win10-specific\zlib\prebuilt\$arch",
        "win10-specific\angle\prebuilt\$arch"
    )
}

$script:Missing = @()

if (-not $SkipHeaders) {
    Write-Host "-- headers --"
    foreach ($rel in $HeaderDirs) {
        $s = Join-Path $src $rel
        $d = Join-Path $dst $rel
        if (-not (Test-Path -LiteralPath $s)) {
            $script:Missing += "  $rel"
            Write-Warning "source missing, skipping: $rel"
            continue
        }
        if (-not (Test-Path -LiteralPath $d)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
        # Trailing \* merges the contents instead of nesting the directory.
        Copy-Item -Path (Join-Path $s '*') -Destination $d -Recurse -Force
        Write-Host "merged:      $rel"
    }
    Write-Host ""
}

$installed = @()
foreach ($arch in $Arches) {
    Write-Host "-- $arch --"
    $any = $false
    foreach ($rel in (Get-ArchDirs $arch)) {
        $s = Join-Path $src $rel
        $d = Join-Path $dst $rel
        if (-not (Test-Path -LiteralPath $s)) {
            $script:Missing += "  $rel"
            Write-Warning "source missing, skipping: $rel"
            continue
        }
        if (Test-Path -LiteralPath $d) {
            Write-Host "overwriting: $rel"
            Remove-Item -LiteralPath $d -Recurse -Force
        } else {
            Write-Host "adding:      $rel"
        }
        $parent = Split-Path -Parent $d
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Copy-Item -LiteralPath $s -Destination $d -Recurse -Force
        $any = $true
    }
    if ($any) { $installed += $arch }
    Write-Host ""
}

if ($installed.Count -eq 0) {
    throw "nothing installed -- run build_win10_uwp.bat first"
}

if ($script:Missing.Count -gt 0) {
    Write-Host "-- not found under cocos2d-x-deps --"
    $script:Missing | Sort-Object -Unique | ForEach-Object { Write-Host $_ }
    Write-Host ""
}

Write-Host "== UWP deps installed under $dst for: $($installed -join ', ') =="
Write-Host ""
Write-Host "Next on the cocos2d-x side:"
Write-Host "  - the .vcxproj/.props still need platform configurations for any"
Write-Host "    architecture that did not have one (ARM64 in particular)"
Write-Host "  - library name references have to follow the modern vcpkg names:"
Write-Host "    openssl 3.x DLLs (libcrypto-3-<arch>.dll, not libcrypto-1_1.dll),"
Write-Host "    z.dll / z.lib for zlib, libcurl.lib for curl"
Write-Host "  - ARM32 (arm-uwp) is no longer produced; drop its configurations"
