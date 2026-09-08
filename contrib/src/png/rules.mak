# PNG
PNG_VERSION := 1.6.58
PNG_URL := $(SF)/libpng/libpng16/$(PNG_VERSION)/libpng-$(PNG_VERSION).tar.xz


$(TARBALLS)/libpng-$(PNG_VERSION).tar.xz:
	$(call download,$(PNG_URL))

.sum-png: libpng-$(PNG_VERSION).tar.xz


png: libpng-$(PNG_VERSION).tar.xz .sum-png
	$(UNPACK)
	$(MOVE)

DEPS_png = zlib $(DEPS_zlib)

.png: png
	# Regenerate before configuring, not after: leaving configure newer than
	# the Makefile it produced sends GNU make 3.81 (what Xcode still ships)
	# down its remake-the-makefile path, where it segfaults.
	$(RECONF)
	cd $< && $(HOSTVARS) ./configure $(HOSTCONF)
	cd $< && $(MAKE) install
	touch $@
