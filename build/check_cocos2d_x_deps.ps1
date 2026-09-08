#Requires -Version 5.0
<#
Audits an installed dependency tree for DLLs that would fail to load.

    powershell -File check_cocos2d_x_deps.ps1 -Path <cocos2d-x tree or external dir>
    powershell -File check_cocos2d_x_deps.ps1 -Path ..\contrib\install-win10\external\cocos2d-x-deps

Every DLL in the tree is asked what it imports, and each import is resolved
against the tree itself. An import is satisfied only by a DLL of the *same
machine type*, so an x64 copy cannot stand in for the win32 one -- that is the
mistake a plain by-name check makes.

Imports are reported as MISSING unless they are:
  - present in the tree for the same architecture
  - a Windows system DLL (found in System32, or an api-ms-* / ext-ms-* stub)
  - a UWP CRT framework DLL (*_APP.dll), which the VCLibs framework package
    supplies to the app at deployment time rather than the app shipping it

This is how jpeg62.dll / liblzma.dll (pulled in by a shared libtiff) and
fmt.dll (pulled in by current openal-soft) were found: nothing links them, so
the build succeeds and only the load fails, sometimes not until the first TIFF
is decoded or the first sound plays.

Exit code is 1 when anything is missing, so this can gate a build.
#>
param(
    # A cocos2d-x working tree, its external\ directory, or any directory of
    # prebuilt binaries (the UWP staging tree works too).
    [Parameter(Mandatory=$true)][string]$Path,

    # Print every DLL and what satisfied its imports.
    [switch]$Detailed
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path)) { throw "not found: $Path" }
$root = (Get-Item -LiteralPath $Path).FullName
if (Test-Path -LiteralPath (Join-Path $root 'external')) {
    $root = (Get-Item -LiteralPath (Join-Path $root 'external')).FullName
}

# Resolve-Path and Get-ChildItem can disagree on short vs long path form, so
# only strip the prefix when it really is one; otherwise show the full path
# rather than a slice taken at the wrong offset.
function Get-Rel([string]$full, [string]$base) {
    if ($full.StartsWith($base, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($base.Length).TrimStart('\')
    }
    return $full
}

function Get-DumpBin {
    $vs = Get-ChildItem "${env:ProgramFiles}\Microsoft Visual Studio\*\*\VC\Tools\MSVC\*\bin\Host*\x64\dumpbin.exe" -ErrorAction SilentlyContinue
    if (-not $vs) {
        $vs = Get-ChildItem "${env:ProgramFiles(x86)}\Microsoft Visual Studio\*\*\VC\Tools\MSVC\*\bin\Host*\x64\dumpbin.exe" -ErrorAction SilentlyContinue
    }
    if (-not $vs) { throw "dumpbin.exe not found -- run this from a machine with Visual Studio installed" }
    ($vs | Sort-Object FullName | Select-Object -Last 1).FullName
}

# PE machine type, straight out of the COFF header.
function Get-Machine([string]$file) {
    try {
        $fs = [System.IO.File]::OpenRead($file)
        try {
            $br = New-Object System.IO.BinaryReader($fs)
            $fs.Position = 0x3C
            $peOff = $br.ReadInt32()
            $fs.Position = $peOff + 4
            $m = $br.ReadUInt16()
        } finally { $fs.Dispose() }
    } catch { return 'unreadable' }
    switch ($m) {
        0x014C  { 'x86' }
        0x8664  { 'x64' }
        0xAA64  { 'arm64' }
        0x01C4  { 'arm' }
        default { ('0x{0:X}' -f $m) }
    }
}

$dumpbin = Get-DumpBin
$dlls = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter *.dll -ErrorAction SilentlyContinue)
if ($dlls.Count -eq 0) { throw "no DLLs found under $root" }

Write-Host "== checking $($dlls.Count) DLLs under $root =="
Write-Host ""

# name (lowercase) -> set of machine types present in the tree
$index = @{}
$machineOf = @{}
foreach ($d in $dlls) {
    $m = Get-Machine $d.FullName
    $machineOf[$d.FullName] = $m
    $key = $d.Name.ToLower()
    if (-not $index.ContainsKey($key)) { $index[$key] = @{} }
    $index[$key][$m] = $true
}

$missing   = @{}
$framework = @{}

foreach ($d in $dlls) {
    $mine = $machineOf[$d.FullName]
    $deps = & $dumpbin /DEPENDENTS $d.FullName 2>$null |
            Select-String -Pattern '^\s+(\S+\.dll)' |
            ForEach-Object { $_.Matches.Groups[1].Value }

    $rel = Get-Rel $d.FullName $root
    if ($Detailed) { Write-Host "$rel  [$mine]" }

    foreach ($dep in $deps) {
        $l = $dep.ToLower()
        $verdict = 'MISSING'
        if ($index.ContainsKey($l) -and $index[$l].ContainsKey($mine)) {
            $verdict = 'in tree'
        } elseif ($l -like 'api-ms-*' -or $l -like 'ext-ms-*' -or (Test-Path "$env:SystemRoot\System32\$dep")) {
            $verdict = 'system'
        } elseif ($l -like '*_app.dll') {
            $verdict = 'UWP framework'
            $framework["$dep"] = $true
        } elseif ($index.ContainsKey($l)) {
            # Present, but only built for another architecture -- still a miss.
            $verdict = "MISSING for $mine (tree only has $(($index[$l].Keys | Sort-Object) -join ', '))"
        }
        if ($Detailed) { Write-Host ("    {0,-28} {1}" -f $dep, $verdict) }
        if ($verdict -like 'MISSING*') { $missing["$dep  <- $rel  [$mine]  $verdict"] = $true }
    }
}

if ($framework.Count -gt 0) {
    Write-Host "-- supplied by the UWP VCLibs framework package (not shipped here) --"
    $framework.Keys | Sort-Object | ForEach-Object { Write-Host "    $_" }
    Write-Host ""
}

if ($missing.Count -eq 0) {
    Write-Host "== OK: every DLL import resolves =="
    exit 0
}

Write-Host "-- unmet DLL dependencies --"
$missing.Keys | Sort-Object | ForEach-Object { Write-Host "    $_" }
Write-Host ""
Write-Host "== $($missing.Count) unmet dependencies =="
Write-Host "Either install the missing DLL alongside the one that needs it, or build"
Write-Host "that library statically so it has nothing to load at run time."
exit 1
