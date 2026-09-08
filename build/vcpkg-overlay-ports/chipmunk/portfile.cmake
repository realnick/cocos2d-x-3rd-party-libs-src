# cocos2d-x flavoured Chipmunk2D.
#
# The upstream vcpkg port builds Chipmunk 7.0.3 with the stock headers, whose
# chipmunk_types.h defaults to `CP_USE_DOUBLES 1` (cpFloat == double).
# cocos2d-x ships its own chipmunk headers (external/chipmunk/include) which are
# a patched 7.0.1 with `CP_USE_DOUBLES 0` (cpFloat == float), and it compiles
# CCPhysics*.cpp against those headers -- the prebuilt library is only linked,
# never re-declared.  Mixing the two means every cpVect/cpFloat crossing the ABI
# is read at the wrong size and stride, which is why the UWP app crashes inside
# chipmunk.
#
# So build exactly what cocos2d-x's headers describe: 7.0.1 with the same
# cocos2d.patch / cocos2d_winrt.patch this repo applies on every other platform
# (see contrib/src/chipmunk/rules.mak), as a static library like the existing
# arm/win32/x64 win10 prebuilts.

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO slembcke/Chipmunk2D
    REF "Chipmunk-${VERSION}"
    SHA512 33b5afa56adfe693e5115c9b73fa65a51ccbc20a22b23bfaf58bf7e8ff9b2af4c06d4af89ca5958a2d6c5c20c757c7b834593589289325d480d90e9eff1909d7
    HEAD_REF master
    PATCHES
        cocos2d.patch
        cocos2d_winrt.patch
        build-fixes.patch
)

# cocos2d-x's win10 prebuilts for arm/win32/x64 are static libs and the engine
# links chipmunk.lib directly, so keep arm64 static too regardless of the
# triplet's default (uwp triplets are dynamic).
set(VCPKG_LIBRARY_LINKAGE static)

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        -DBUILD_DEMOS=OFF
        -DINSTALL_DEMOS=OFF
        -DBUILD_SHARED=OFF
        -DBUILD_STATIC=ON
        -DINSTALL_STATIC=ON
)

vcpkg_cmake_install()

if(NOT VCPKG_BUILD_TYPE OR VCPKG_BUILD_TYPE STREQUAL "debug")
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
endif()

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE.txt")
