# libuv

LIBUV_VERSION := 1.52.1
LIBUV_URL := https://dist.libuv.org/dist/v$(LIBUV_VERSION)/libuv-v$(LIBUV_VERSION).tar.gz

$(TARBALLS)/libuv-v$(LIBUV_VERSION).tar.gz:
	$(call download,$(LIBUV_URL))

.sum-uv: libuv-v$(LIBUV_VERSION).tar.gz

uv: libuv-v$(LIBUV_VERSION).tar.gz .sum-uv
	$(UNPACK)
	$(MOVE)

ifdef HAVE_ANDROID
cmake_android_def = -DANDROID=1 -DCMAKE_SYSTEM_NAME=Android
endif

.uv: uv toolchain.cmake
	cd $< && $(HOSTVARS) CFLAGS="$(CFLAGS) $(EX_ECFLAGS)" $(CMAKE) -DBUILD_TESTING=OFF -DLIBUV_BUILD_SHARED=OFF $(cmake_android_def) $(make_option)
	cd $< && $(MAKE) VERBOSE=1 install
	touch $@
