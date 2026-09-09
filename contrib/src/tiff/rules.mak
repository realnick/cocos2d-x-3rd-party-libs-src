# tiff

TIFF_VERSION := 4.7.2
TIFF_URL := https://download.osgeo.org/libtiff/tiff-$(TIFF_VERSION).tar.gz

$(TARBALLS)/tiff-$(TIFF_VERSION).tar.gz:
	$(call download,$(TIFF_URL))

.sum-tiff: tiff-$(TIFF_VERSION).tar.gz

tiff: tiff-$(TIFF_VERSION).tar.gz .sum-tiff
	$(UNPACK)
	$(UPDATE_AUTOCONFIG)
	$(MOVE)

.tiff: tiff
	$(RECONF)
	cd $< && $(HOSTVARS) ./configure $(HOSTCONF) \
		--disable-jpeg \
		--disable-zlib \
		--disable-cxx \
		--disable-tools \
		--without-x
	cd $< && $(MAKE) -C port && $(MAKE) -C libtiff
	# Only libtiff itself. A top-level install also builds contrib/ (addtiffo and
	# friends) on top of the tools --disable-tools already drops, and those need
	# log2(), which 32-bit Android's libm does not have below API 18. The library
	# and its headers are all cocos2d-x takes.
	cd $< && $(MAKE) -C libtiff install
	touch $@
