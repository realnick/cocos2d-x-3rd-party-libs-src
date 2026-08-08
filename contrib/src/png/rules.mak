# PNG
PNG_VERSION := 1.6.44
PNG_URL := $(SF)/libpng/libpng16/$(PNG_VERSION)/libpng-$(PNG_VERSION).tar.xz


$(TARBALLS)/libpng-$(PNG_VERSION).tar.xz:
	$(call download,$(PNG_URL))

.sum-png: libpng-$(PNG_VERSION).tar.xz


png: libpng-$(PNG_VERSION).tar.xz .sum-png
	$(UNPACK)
	$(MOVE)

DEPS_png = zlib $(DEPS_zlib)

.png: png
	cd $< && $(HOSTVARS) ./configure $(HOSTCONF)
	cd $< && rm -f aclocal.m4
	cd $< && aclocal && autoconf
	cd $< && $(MAKE) install
	touch $@
