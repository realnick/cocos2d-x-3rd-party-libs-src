# websockets

WEBSOCKETS_VERSION := 4.5.8
WEBSOCKETS_URL := $(GITHUB)/warmcat/libwebsockets/archive/refs/tags/v$(WEBSOCKETS_VERSION).tar.gz

$(TARBALLS)/libwebsockets-$(WEBSOCKETS_VERSION).tar.gz:
	$(call download,$(WEBSOCKETS_URL))

.sum-websockets: libwebsockets-$(WEBSOCKETS_VERSION).tar.gz

websockets: libwebsockets-$(WEBSOCKETS_VERSION).tar.gz .sum-websockets
	$(UNPACK)
	$(MOVE)

ifdef HAVE_TIZEN
EX_ECFLAGS = -fPIC
endif


DEPS_websockets = zlib $(DEPS_zlib)
DEPS_websockets = openssl $(DEPS_openssl)
DEPS_websockets = uv $(DEPS_uv)

# The iOS and tvOS SDKs have no <net/route.h>. lws already guards that include
# behind LWS_DETECTED_PLAT_IOS, but nothing sets it here: our generated
# toolchain file says CMAKE_SYSTEM_NAME=Darwin, not iOS, so lws cannot tell.
ifdef HAVE_IOS
make_option=-DLWS_DETECTED_PLAT_IOS=1
endif

ifdef HAVE_TVOS
make_option=-DLWS_WITHOUT_DAEMONIZE=1 -DLWS_DETECTED_PLAT_IOS=1
endif

.websockets: websockets .zlib .openssl .uv toolchain.cmake
	# LWS_WITHOUT_TESTAPPS covers what the old per-test LWS_WITHOUT_TEST_*
	# switches used to; the test apps want a host toolchain we do not have when
	# cross compiling. LWS_WITH_MINIMAL_EXAMPLES stays off (its default) for the
	# same reason. DISABLE_WERROR replaces the old remove-werror.patch: lws
	# builds with -Werror, and the cross-compile flags we pass produce warnings
	# it would otherwise turn fatal (on mac, -mmacosx-version-min against
	# CMake's own -target arm64-apple-macos11).
	cd $< && $(HOSTVARS) CFLAGS="$(CFLAGS) $(EX_ECFLAGS)" $(CMAKE) -DLWS_WITH_LIBUV=ON -DLWS_WITH_SSL=ON -DLWS_WITH_SHARED=OFF -DLWS_WITHOUT_TESTAPPS=ON -DLWS_IPV6=ON -DDISABLE_WERROR=ON $(make_option)
	cd $< && $(MAKE) VERBOSE=1 install
	touch $@
