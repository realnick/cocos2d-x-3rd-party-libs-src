# freetype overlay port

A copy of vcpkg's `ports/freetype` (2.14.3) with one extra patch,
`uwp-ftsystem-createfile.patch`, so that `freetype:x86-uwp` links.

Upstream's `builds/windows/ftsystem.c` only compiles its `CreateFile2` shim
under `_WINRT_DLL`, which MSVC predefines only for `/ZW` (C++/CX) builds — not
for the plain C build vcpkg does. Without the shim, `FT_Stream_Open` references
the real `CreateFileA`. `WindowsApp.lib` still exports that for x64 and arm64,
so those link, but the x86 one does not export it at all and the build fails
with `LNK2019: unresolved external symbol _CreateFileA`.

The patch keys the shim off the app family instead of `_WINRT_DLL`, so every
UWP architecture takes the same `CreateFile2` path.

**When updating vcpkg**, re-copy `ports/freetype` over this directory and
re-apply the change, keeping `uwp-ftsystem-createfile.patch` in the `PATCHES`
list of `portfile.cmake`. If upstream fixes this itself, drop the overlay
entirely — check whether `#ifdef _WINRT_DLL` in `builds/windows/ftsystem.c` has
been replaced by an app-family check.
