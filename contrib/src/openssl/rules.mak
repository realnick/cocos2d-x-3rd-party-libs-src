# OPENSSL
# 1.1.1w is the final 1.1.1 LTS release (Sep 2023) - the 1.1.1 branch itself
# is EOL, but this stays API-compatible with 1.1.1k while picking up ~2.5
# years of security fixes. A 3.x upgrade is a separate, larger decision
# (engine removal / API changes could affect curl and websockets).
OPENSSL_VERSION := 1.1.1w
OPENSSL_URL := https://www.openssl.org/source/openssl-$(OPENSSL_VERSION).tar.gz

OPENSSL_EXTRA_CONFIG_1=no-shared no-unit-test
OPENSSL_EXTRA_CONFIG_2=

ifdef HAVE_MACOSX
ifeq ($(MY_TARGET_ARCH),x86_64)
OPENSSL_CONFIG_VARS=darwin64-x86_64-cc
OPENSSL_ARCH=-m64
endif

ifeq ($(MY_TARGET_ARCH),i386)
OPENSSL_CONFIG_VARS=BSD-generic32
OPENSSL_ARCH=-m32
endif

ifeq ($(MY_TARGET_ARCH),arm64)
OPENSSL_CONFIG_VARS=darwin64-arm64-cc
OPENSSL_ARCH=-m64
endif
endif

ifdef HAVE_LINUX
ifeq ($(MY_TARGET_ARCH),x86_64)
OPENSSL_CONFIG_VARS=linux-x86_64
OPENSSL_ARCH=-m64
endif

ifeq ($(MY_TARGET_ARCH),i386)
OPENSSL_CONFIG_VARS=linux-elf
OPENSSL_ARCH=-m32
endif
endif

ifdef HAVE_TIZEN
ifeq ($(MY_TARGET_ARCH),x86)
OPENSSL_CONFIG_VARS=linux-elf
OPENSSL_ARCH=-m32
OPENSSL_EXTRA_CONFIG_2=no-async
endif
ifeq ($(MY_TARGET_ARCH),armv7)
OPENSSL_CONFIG_VARS=linux-generic32
endif
endif

ifdef HAVE_ANDROID
export ANDROID_SYSROOT=$(ANDROID_TOOLCHAIN_PATH)/sysroot
export SYSROOT=$(ANDROID_SYSROOT)
export NDK_SYSROOT=$(ANDROID_SYSROOT)
export ANDROID_NDK_SYSROOT=$(ANDROID_SYSROOT)
export CROSS_SYSROOT=$(ANDROID_SYSROOT)

ifeq ($(MY_TARGET_ARCH),arm64-v8a)
OPENSSL_CONFIG_VARS=android64-aarch64
endif

ifeq ($(MY_TARGET_ARCH),armeabi-v7a)
OPENSSL_CONFIG_VARS=android-armeabi
endif

ifeq ($(MY_TARGET_ARCH),armeabi)
OPENSSL_CONFIG_VARS=android-armeabi
endif

ifeq ($(MY_TARGET_ARCH),x86)
OPENSSL_CONFIG_VARS=android-x86
endif
endif

ifdef HAVE_IOS

ifeq ($(MY_TARGET_ARCH),armv7)
IOS_PLATFORM=OS
# Stock openssl's own "ios-cross" target hardcodes "-arch armv7" (see
# Configurations/15-ios.conf), so armv7s built through it silently produces
# an armv7 object too. Use our own per-arch targets (config/20-ios-tvos-
# cross.conf) so each arch actually gets its own -arch flag.
OPENSSL_CONFIG_VARS=ios-cross-armv7
OPENSSL_EXTRA_CONFIG_2=no-async
endif

ifeq ($(MY_TARGET_ARCH),arm64)
ifeq ($(IOS_FORCE_SIMULATOR),yes)
IOS_PLATFORM=Simulator
OPENSSL_CONFIG_VARS=ios-sim-cross-arm64
else
IOS_PLATFORM=OS
OPENSSL_CONFIG_VARS=ios64-cross
endif
OPENSSL_EXTRA_CONFIG_2=no-async
endif
ifeq ($(MY_TARGET_ARCH),armv7s)
IOS_PLATFORM=OS
OPENSSL_CONFIG_VARS=ios-cross-armv7s
OPENSSL_EXTRA_CONFIG_2=no-async
endif

ifeq ($(MY_TARGET_ARCH),i386)
IOS_PLATFORM=Simulator
OPENSSL_CONFIG_VARS=ios-sim-cross-i386
OPENSSL_EXTRA_CONFIG_2=no-async
endif

ifeq ($(MY_TARGET_ARCH),x86_64)
IOS_PLATFORM=Simulator
OPENSSL_CONFIG_VARS=ios-sim-cross-x86_64
OPENSSL_EXTRA_CONFIG_2=no-async
endif

CUR_MAKEFILE_DIR:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

# Set reference to custom configuration (OpenSSL 1.1.0)
# See: https://github.com/openssl/openssl/commit/afce395cba521e395e6eecdaf9589105f61e4411
export OPENSSL_LOCAL_CONFIG_DIR=${CUR_MAKEFILE_DIR}/config

export CROSS_TOP=$(shell xcode-select -print-path)/Platforms/iPhone${IOS_PLATFORM}.platform/Developer
export CROSS_SDK=iPhone${IOS_PLATFORM}.sdk

endif

ifdef HAVE_TVOS

ifeq ($(MY_TARGET_ARCH),arm64)
TVOS_PLATFORM=OS
OPENSSL_CONFIG_VARS=tvos64-cross-arm64
OPENSSL_EXTRA_CONFIG_2=no-async
endif
ifeq ($(MY_TARGET_ARCH),x86_64)
TVOS_PLATFORM=Simulator
OPENSSL_CONFIG_VARS=tvos-sim-cross-x86_64
OPENSSL_EXTRA_CONFIG_2=no-async
endif

CUR_MAKEFILE_DIR:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

# Set reference to custom configuration (OpenSSL 1.1.0)
# See: https://github.com/openssl/openssl/commit/afce395cba521e395e6eecdaf9589105f61e4411
export OPENSSL_LOCAL_CONFIG_DIR=${CUR_MAKEFILE_DIR}/config

export CROSS_TOP=$(shell xcode-select -print-path)/Platforms/AppleTV${TVOS_PLATFORM}.platform/Developer
export CROSS_SDK=AppleTV${TVOS_PLATFORM}.sdk

endif

$(TARBALLS)/openssl-$(OPENSSL_VERSION).tar.gz:
	$(call download,$(OPENSSL_URL))

.sum-openssl: openssl-$(OPENSSL_VERSION).tar.gz

openssl: openssl-$(OPENSSL_VERSION).tar.gz .sum-openssl
	$(UNPACK)
ifdef HAVE_ANDROID
	$(APPLY) $(SRC)/openssl/android-clang.patch
endif
	$(MOVE)

.openssl: openssl
	cd $< && $(HOSTVARS_PIC) ./Configure $(OPENSSL_CONFIG_VARS) --prefix=$(PREFIX) ${OPENSSL_ARCH} $(OPENSSL_EXTRA_CONFIG_1) $(OPENSSL_EXTRA_CONFIG_2)
ifdef HAVE_IOS
	cd $< && perl -i -pe "s|^CFLAGS=(.*) -DNDEBUG (.*)-O3|CFLAGS=\\1 \\2 ${OPTIM} ${ENABLE_BITCODE}|g" Makefile
	cd $< && perl -i -pe "s|^CFLAGS_Q=(.*) -DNDEBUG (.*)|CFLAGS_Q=\\1 \\2 ${OPTIM} ${ENABLE_BITCODE}|g" Makefile
endif
ifdef HAVE_TVOS
	cd $< && perl -i -pe "s|^CFLAGS=(.*) -DNDEBUG (.*)-O3|CFLAGS=\\1 \\2 ${OPTIM} ${ENABLE_BITCODE}|g" Makefile
	cd $< && perl -i -pe "s|^CFLAGS_Q=(.*) -DNDEBUG (.*)|CFLAGS_Q=\\1 \\2 ${OPTIM} ${ENABLE_BITCODE}|g" Makefile
endif
ifdef HAVE_LINUX
ifndef HAVE_ANDROID
	cd $< && perl -i -pe "s|^CFLAGS=(.*) -DNDEBUG (.*)-O3|CFLAGS=\\1 \\2 ${EXTRA_CFLAGS} ${OPTIM}|g" Makefile
	cd $< && perl -i -pe "s|^CFLAGS_Q=(.*) -DNDEBUG (.*)|CFLAGS_Q=\\1 \\2 ${EXTRA_CFLAGS} ${OPTIM}|g" Makefile
endif
endif
ifdef HAVE_MACOSX
	cd $< && perl -i -pe "s|^CFLAGS=(.*) -DNDEBUG (.*)-O3|CFLAGS=\\1 \\2 ${OPTIM}|g" Makefile
	cd $< && perl -i -pe "s|^CFLAGS_Q=(.*) -DNDEBUG (.*)|CFLAGS_Q=\\1 \\2 ${OPTIM}|g" Makefile
endif
	cd $< && $(MAKE) install_sw
	touch $@
