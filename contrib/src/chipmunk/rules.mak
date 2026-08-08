# chipmunk

CHIPMUNK_VERSION := 7.0.1
# chipmunk-physics.net's official mirror serves an invalid/self-signed TLS
# cert; pull the same tagged release from the project's GitHub mirror instead.
CHIPMUNK_URL := https://codeload.github.com/slembcke/Chipmunk2D/tar.gz/refs/tags/Chipmunk-$(CHIPMUNK_VERSION)

$(TARBALLS)/Chipmunk-$(CHIPMUNK_VERSION).tgz:
	$(call download,$(CHIPMUNK_URL))

.sum-chipmunk: Chipmunk-$(CHIPMUNK_VERSION).tgz

chipmunk: Chipmunk-$(CHIPMUNK_VERSION).tgz .sum-chipmunk
	$(UNPACK)
	$(MOVE)


.chipmunk: chipmunk toolchain.cmake
	$(APPLY) $(SRC)/chipmunk/cocos2d.patch
	cd $< && $(HOSTVARS_PIC) $(CMAKE) . -DBUILD_DEMOS=off
	cd $< && $(MAKE) VERBOSE=1 install
	touch $@
