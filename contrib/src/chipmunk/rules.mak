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
# The GitHub archive unpacks to <repo>-<tag>, i.e. Chipmunk2D-Chipmunk-7.0.1,
# while UNPACK_DIR (and so MOVE) is derived from the tarball's own name.
	mv Chipmunk2D-Chipmunk-$(CHIPMUNK_VERSION) Chipmunk-$(CHIPMUNK_VERSION)
# Patch here, alongside every other recipe, rather than in .chipmunk: that
# rule reruns on any later failure and re-applying the patch to already-
# patched sources fails, masking the real error.
	$(APPLY) $(SRC)/chipmunk/cocos2d.patch
	$(MOVE)


.chipmunk: chipmunk toolchain.cmake
	cd $< && $(HOSTVARS_PIC) $(CMAKE) . -DBUILD_DEMOS=off
	cd $< && $(MAKE) VERBOSE=1 install
	touch $@
