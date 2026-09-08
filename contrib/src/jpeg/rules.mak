# jpeg
# libjpeg-turbo, the same implementation the Windows (vcpkg) side installs.
# This used to build plain IJG jpeg 9d: turbo is a different codebase with a
# CMake build, but it exposes the libjpeg API and installs under the same
# libjpeg.a / j*.h names, so nothing downstream changes.

JPEG_VERSION := 3.2.0
JPEG_URL := $(GITHUB)/libjpeg-turbo/libjpeg-turbo/releases/download/$(JPEG_VERSION)/libjpeg-turbo-$(JPEG_VERSION).tar.gz

$(TARBALLS)/libjpeg-turbo-$(JPEG_VERSION).tar.gz:
	$(call download,$(JPEG_URL))

.sum-jpeg: libjpeg-turbo-$(JPEG_VERSION).tar.gz

jpeg: libjpeg-turbo-$(JPEG_VERSION).tar.gz .sum-jpeg
	$(UNPACK)
	$(MOVE)

# libjpeg-turbo picks its SIMD implementation off CMAKE_SYSTEM_PROCESSOR, which
# the generated toolchain file does not set -- left alone it inherits the build
# host's and cross builds get the wrong one. $(ARCH) cannot be used here either:
# every iOS arch shares the host triple "arm-apple-darwin". So map the target
# arch by hand.
ifneq ($(filter $(MY_TARGET_ARCH),arm64 arm64-v8a arm64_simulator),)
JPEG_PROCESSOR := aarch64
endif
ifneq ($(filter $(MY_TARGET_ARCH),armv7 armv7s armeabi armeabi-v7a),)
JPEG_PROCESSOR := arm
endif
ifneq ($(filter $(MY_TARGET_ARCH),i386 x86),)
JPEG_PROCESSOR := i386
endif
ifneq ($(filter $(MY_TARGET_ARCH),x86_64),)
JPEG_PROCESSOR := x86_64
endif

# The arm SIMD paths are plain C intrinsics and assemble with the compiler we
# already have; the x86 ones need nasm, which is not a prerequisite of this repo.
ifneq ($(filter $(JPEG_PROCESSOR),i386 x86_64),)
JPEG_SIMD := -DWITH_SIMD=OFF
endif

.jpeg: jpeg toolchain.cmake
	cd $< && $(HOSTVARS) CFLAGS="$(CFLAGS) $(EX_ECFLAGS)" $(CMAKE) \
		-DCMAKE_SYSTEM_PROCESSOR=$(JPEG_PROCESSOR) \
		-DENABLE_SHARED=OFF \
		-DENABLE_STATIC=ON \
		-DWITH_TURBOJPEG=OFF \
		$(JPEG_SIMD)
	cd $< && $(MAKE) install
	touch $@
