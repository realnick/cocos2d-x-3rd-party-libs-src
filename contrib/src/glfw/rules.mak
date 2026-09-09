# GLFW
GLFW_VERSION := 3.4
#GLFW_URL := $(GITHUB)/glfw/glfw/releases/download/$(GLFW_VERSION)/glfw-$(GLFW_VERSION).zip
GLFW_URL := https://codeload.github.com/glfw/glfw/tar.gz/$(GLFW_VERSION)


$(TARBALLS)/glfw-$(GLFW_VERSION).tar.gz:
	$(call download,$(GLFW_URL))

.sum-glfw: glfw-$(GLFW_VERSION).tar.gz

glfw: glfw-$(GLFW_VERSION).tar.gz .sum-glfw
	$(UNPACK)
	$(APPLY) $(SRC)/glfw/dont_include_applicationservices.patch
	$(MOVE)

# This calls cmake directly rather than through $(CMAKE)/toolchain.cmake, so the
# target architecture has to be named here: CMake otherwise adds the host's own
# -arch alongside the one in CFLAGS and produces a universal binary, which the
# per-arch fat-library step then cannot lipo with the other arch's slice.
ifdef HAVE_MACOSX
GLFW_CMAKE_ARCH = -DCMAKE_OSX_ARCHITECTURES=$(ARCH)
endif

.glfw: glfw
	cd $< && $(HOSTVARS) CFLAGS="$(CFLAGS) $(EX_ECFLAGS)"  cmake .  -DGLFW_BUILD_DOCS=0 $(GLFW_CMAKE_ARCH) -DCMAKE_INSTALL_PREFIX=$(PREFIX)
	cd $< && $(MAKE) VERBOSE=1 install
	touch $@
