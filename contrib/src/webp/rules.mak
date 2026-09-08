# webp

WEBP_VERSION := 1.6.0
WEBP_URL := http://downloads.webmproject.org/releases/webp/libwebp-$(WEBP_VERSION).tar.gz

$(TARBALLS)/libwebp-$(WEBP_VERSION).tar.gz:
	$(call download,$(WEBP_URL))

.sum-webp: libwebp-$(WEBP_VERSION).tar.gz

ifdef HAVE_ANDROID
ifeq ($(MY_TARGET_ARCH),armeabi-v7a)
	mkdir -p $(PREFIX)/lib
	cp $(PREFIX)/../../src/webp/libcpufeatures.a $(PREFIX)/lib/
endif
endif

webp: libwebp-$(WEBP_VERSION).tar.gz .sum-webp
	$(UNPACK)
	$(UPDATE_AUTOCONFIG)
	$(MOVE)

.webp: webp
	# The cwebp/dwebp example tools (not libwebp.a itself, which we actually
	# need) optionally link against libjpeg/libpng/libtiff/giflib for format
	# conversion. Disabling that avoids a build break where webp's example
	# code assumes an older libjpeg callback signature than what's installed.
	cd $< && $(HOSTVARS) ./configure $(HOSTCONF) --disable-jpeg --disable-png --disable-tiff --disable-gif
	cd $< && $(MAKE)
	cd $< && $(MAKE) install
	touch $@
