@echo off
setlocal enabledelayedexpansion

REM Builds the cocos2d-x 3rd party dependencies for Windows 10 Universal (UWP)
REM with vcpkg.
REM
REM   build_win10_uwp.bat                    -> win32 x64 arm64
REM   build_win10_uwp.bat x64                -> just x64
REM   build_win10_uwp.bat win32 arm64        -> those two
REM   build_win10_uwp.bat clean              -> wipe the tree, then build all
REM   build_win10_uwp.bat clean x64          -> wipe, then build x64
REM
REM Architecture tokens: win32 | x64 | arm64. The token is also the name of the
REM per-arch output directory, matching cocos2d-x's prebuilt\win10\<arch>.
REM
REM ARM32 (arm-uwp) is not built. Windows 10 Mobile is gone and the MSVC
REM toolset shipped with current Visual Studio no longer has an arm target --
REM only arm64, x64 and x86 -- so it cannot be produced here any more.
REM
REM This used to install a `cocos2d-x-deps` meta-port from the
REM stammen/vcpkg-cocos2d-x fork, which pinned a different, much older set of
REM versions than build_win10_uwp_arm64.bat did. Both now go through the same
REM microsoft/vcpkg clone and the same overlay ports, so every UWP
REM architecture gets identical versions -- and the same versions as
REM build_win32_desktop.bat, as long as they share the clone.
REM
REM Set COCOS_VCPKG_DIR to use a vcpkg clone somewhere else.

SET START_DIR=%~dp0
if "%START_DIR:~-1%"=="\" set START_DIR=%START_DIR:~0,-1%
SET INSTALL_DIR=%START_DIR%\..\contrib\install-win10
SET VCPKG_DIR=%INSTALL_DIR%\vcpkg
if not "%COCOS_VCPKG_DIR%"=="" set VCPKG_DIR=%COCOS_VCPKG_DIR%
SET OVERLAY_PORTS=%START_DIR%\vcpkg-overlay-ports
SET EXTERNAL_DIR=%INSTALL_DIR%\external\cocos2d-x-deps

SET PKGS=zlib openssl curl freetype libogg libvorbis libwebsockets sqlite3 chipmunk

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
if "%ARCHES%"=="" set ARCHES=win32 x64 arm64

echo Install dir:     %INSTALL_DIR%
echo Vcpkg dir:       %VCPKG_DIR%
echo Overlay ports:   %OVERLAY_PORTS%
echo Architectures:  %ARCHES%

if "%DO_CLEAN%"=="1" (
	taskkill /F /IM cl.exe      >nul 2>&1
	taskkill /F /IM link.exe    >nul 2>&1
	taskkill /F /IM vcpkg.exe   >nul 2>&1
	taskkill /F /IM MSBuild.exe >nul 2>&1
	if exist "%INSTALL_DIR%\external"         rmdir /s /q "%INSTALL_DIR%\external"
	if exist "%INSTALL_DIR%\vcpkg-cocos2d-x"  rmdir /s /q "%INSTALL_DIR%\vcpkg-cocos2d-x"
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
echo === cocos2d-x-deps layout ready at %EXTERNAL_DIR% ===
echo === architectures: %ARCHES% ===
goto :eof


REM --- :build_arch <arch token> -------------------------------------------
:build_arch
setlocal enabledelayedexpansion
set ARCH=%~1
call :triplet %ARCH%
if "!TRIPLET!"=="" (
	echo unknown architecture: %ARCH%  ^(expected win32 ^| x64 ^| arm64^)
	endlocal & exit /b 1
)

echo.
echo ======================================================================
echo  %ARCH%   triplet=!TRIPLET!
echo ======================================================================

for %%P in (%PKGS%) do (
	REM --classic: the overlay ports carry vcpkg.json files of their own, so
	REM running this from inside one would otherwise put vcpkg in manifest
	REM mode, where `install <pkg>:<triplet>` is rejected.
	"%VCPKG_DIR%\vcpkg.exe" install --classic %%P:!TRIPLET! --overlay-ports="%OVERLAY_PORTS%"
	if !ERRORLEVEL! neq 0 endlocal & exit /b !ERRORLEVEL!
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%START_DIR%\assemble_cocos2d_x_deps_uwp.ps1" ^
	-VcpkgInstalled "%VCPKG_DIR%\installed\!TRIPLET!" ^
	-OutDir "%EXTERNAL_DIR%" ^
	-Arch %ARCH%
if !ERRORLEVEL! neq 0 endlocal & exit /b !ERRORLEVEL!

endlocal & exit /b 0


REM --- :triplet <arch token> -> TRIPLET ------------------------------------
:triplet
set TRIPLET=
if /i "%~1"=="win32" set TRIPLET=x86-uwp
if /i "%~1"=="x86"   set TRIPLET=x86-uwp
if /i "%~1"=="x64"   set TRIPLET=x64-uwp
if /i "%~1"=="win64" set TRIPLET=x64-uwp
if /i "%~1"=="arm64" set TRIPLET=arm64-uwp
exit /b 0


:error
echo win10 uwp build error: %ERRORLEVEL%
exit /b %ERRORLEVEL%
