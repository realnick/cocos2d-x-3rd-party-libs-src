@echo off
setlocal enabledelayedexpansion

REM Builds the cocos2d-x 3rd party dependencies for Windows *desktop*
REM (Win32 / x64 / ARM64) with vcpkg, the same way build_win10_uwp_arm64.bat
REM does for UWP.
REM
REM   build_win32_desktop.bat                   -> win32 win64 arm64
REM   build_win32_desktop.bat win64             -> just x64
REM   build_win32_desktop.bat win32 arm64       -> those two
REM   build_win32_desktop.bat clean             -> wipe the tree, then build all
REM   build_win32_desktop.bat clean win64       -> wipe, then build x64
REM
REM Architecture tokens: win32 | win64 | x64 | arm64.
REM
REM This builds the *union* of what cocos2d-x v3 and v4 need; deciding which
REM subset goes where is install_to_cocos2d_x_win32.ps1's job:
REM
REM   powershell -File install_to_cocos2d_x_win32.ps1 -Target v4 ^
REM       -Cocos2dRoot <path to the cocos2d-x working tree>
REM
REM Set COCOS_VCPKG_DIR to reuse an existing vcpkg clone (e.g. the one
REM build_win10_uwp_arm64.bat made under contrib\install-win10\vcpkg) instead
REM of cloning a second copy.

SET START_DIR=%~dp0
if "%START_DIR:~-1%"=="\" set START_DIR=%START_DIR:~0,-1%
SET INSTALL_DIR=%START_DIR%\..\contrib\install-win32
REM One vcpkg clone serves BOTH this script and build_win10_uwp.bat. That is
REM what keeps UWP and desktop on identical library versions -- separate clones
REM drift apart silently. The path is under install-win10 for historical
REM reasons only; it is not UWP-specific.
SET VCPKG_DIR=%START_DIR%\..\contrib\install-win10\vcpkg
if not "%COCOS_VCPKG_DIR%"=="" set VCPKG_DIR=%COCOS_VCPKG_DIR%
SET OVERLAY_PORTS=%START_DIR%\vcpkg-overlay-ports

REM Dynamic triplet: DLL + import lib.
REM   v3 + v4: zlib curl libogg libvorbis mpg123 openal-soft glew libiconv
REM   v4 only: openssl libuv libwebsockets
REM   v3 only: sqlite3
SET DYN_PKGS=zlib openssl curl libuv libwebsockets sqlite3 libogg libvorbis mpg123 openal-soft glew libiconv
REM Static triplet (static lib, dynamic CRT).
REM   v3 + v4: freetype libpng libjpeg-turbo libwebp glfw3 chipmunk
REM   v3 only: libwebsockets -- v3 links a static websockets.lib where v4 uses
REM            the DLL, so libwebsockets is built under both triplets.
REM   v3 only: tiff[core] -- v3 links libtiff statically and xcopies only *.lib
REM            from tiff\prebuilt, so a DLL there would never be deployed. The
REM            [core] feature set drops jpeg, lzma and zip, which is what this
REM            repo's own recipe has always built (--disable-jpeg
REM            --disable-zlib in contrib\src\tiff\rules.mak) and what lets
REM            cocos2d-x link libtiff.lib on its own.
REM freetype[core] drops the png/zlib/brotli/bzip2 default features so the
REM single freetype.lib cocos2d-x links has no unresolved externals.
SET STATIC_PKGS=freetype[core] libpng libjpeg-turbo libwebp glfw3 chipmunk libwebsockets tiff[core]

REM --- argument parsing ----------------------------------------------------
SET DO_CLEAN=0
SET ARCHES=
:parse_args
if "%~1"=="" goto :args_done
if /i "%~1"=="clean" (
	set DO_CLEAN=1
) else (
	set ARCHES=!ARCHES! %~1
)
shift
goto :parse_args
:args_done
if "%ARCHES%"=="" set ARCHES=win32 win64 arm64

echo Install dir:     %INSTALL_DIR%
echo Vcpkg dir:       %VCPKG_DIR%
echo Overlay ports:   %OVERLAY_PORTS%
echo Architectures:  %ARCHES%

if "%DO_CLEAN%"=="1" (
	taskkill /F /IM cl.exe      >nul 2>&1
	taskkill /F /IM link.exe    >nul 2>&1
	taskkill /F /IM vcpkg.exe   >nul 2>&1
	taskkill /F /IM MSBuild.exe >nul 2>&1
	if "%COCOS_VCPKG_DIR%"=="" (
		if exist "%VCPKG_DIR%" rmdir /s /q "%VCPKG_DIR%"
	)
)

if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

REM --- Clone modern microsoft/vcpkg (HEAD) ---
if not exist "%VCPKG_DIR%\.git" (
	if exist "%VCPKG_DIR%" rmdir /s /q "%VCPKG_DIR%"
	git clone https://github.com/microsoft/vcpkg.git "%VCPKG_DIR%"
	if !ERRORLEVEL! neq 0 goto :error
)

REM --- Bootstrap vcpkg.exe ---
if not exist "%VCPKG_DIR%\vcpkg.exe" (
	call "%VCPKG_DIR%\bootstrap-vcpkg.bat" -disableMetrics
	if !ERRORLEVEL! neq 0 goto :error
)

for %%A in (%ARCHES%) do (
	call :build_arch %%A
	if !ERRORLEVEL! neq 0 goto :error
)

echo.
echo === vcpkg trees ready under %VCPKG_DIR%\installed ===
echo === architectures: %ARCHES% ===
echo.
echo Next, install into a cocos2d-x working tree:
echo   powershell -NoProfile -ExecutionPolicy Bypass -File "%START_DIR%\install_to_cocos2d_x_win32.ps1" -Target v4 -Cocos2dRoot ^<path^>
echo   powershell -NoProfile -ExecutionPolicy Bypass -File "%START_DIR%\install_to_cocos2d_x_win32.ps1" -Target v3 -Cocos2dRoot ^<path^>
goto :eof


REM --- :build_arch <arch token> -------------------------------------------
:build_arch
setlocal enabledelayedexpansion
set ARCH=%~1
call :triplet_base %ARCH%
if "!TRIPLET_BASE!"=="" (
	echo unknown architecture: %ARCH%  ^(expected win32 ^| win64 ^| x64 ^| arm64^)
	endlocal & exit /b 1
)
set DYN_TRIPLET=!TRIPLET_BASE!-windows
set STATIC_TRIPLET=!TRIPLET_BASE!-windows-static-md

echo.
echo ======================================================================
echo  %ARCH%   dynamic=!DYN_TRIPLET!   static=!STATIC_TRIPLET!
echo ======================================================================

for %%P in (%DYN_PKGS%) do (
	REM --classic: the overlay ports carry vcpkg.json files of their own, so
	REM running this from inside one would otherwise put vcpkg in manifest
	REM mode, where `install <pkg>:<triplet>` is rejected.
	"%VCPKG_DIR%\vcpkg.exe" install --classic %%P:!DYN_TRIPLET! --overlay-ports="%OVERLAY_PORTS%"
	if !ERRORLEVEL! neq 0 endlocal & exit /b !ERRORLEVEL!
)
for %%P in (%STATIC_PKGS%) do (
	"%VCPKG_DIR%\vcpkg.exe" install --classic "%%P:!STATIC_TRIPLET!" --overlay-ports="%OVERLAY_PORTS%"
	if !ERRORLEVEL! neq 0 endlocal & exit /b !ERRORLEVEL!
)

echo.
echo  %ARCH% done: !DYN_TRIPLET! and !STATIC_TRIPLET! installed

endlocal & exit /b 0


REM --- :triplet_base <arch token> -> TRIPLET_BASE --------------------------
:triplet_base
set TRIPLET_BASE=
if /i "%~1"=="win32" set TRIPLET_BASE=x86
if /i "%~1"=="x86"   set TRIPLET_BASE=x86
if /i "%~1"=="win64" set TRIPLET_BASE=x64
if /i "%~1"=="x64"   set TRIPLET_BASE=x64
if /i "%~1"=="arm64" set TRIPLET_BASE=arm64
exit /b 0


:error
echo win32 desktop build error: %ERRORLEVEL%
exit /b %ERRORLEVEL%
