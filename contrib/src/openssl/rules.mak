# OPENSSL
# 3.x, matching what the Windows (vcpkg) side builds. The 1.1.1 branch this
# used to track went EOL in Sep 2023, and curl 8.21 refuses to configure
# against anything older than 3.0 -- so curl and libwebsockets move with this.
OPENSSL_VERSION := 3.6.3
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
# OpenSSL's Configurations/15-android.conf drives everything off
# $ANDROID_NDK_ROOT. Point it at the standalone toolchain build.sh generates:
# it carries AndroidVersion.txt and a sysroot, which is exactly what openssl
# recognises as a "standalone toolchain". Pointing it at the NDK proper instead
# sends it looking for platforms/android-<api>/arch-<arch>, and the arch it
# derives from the deprecated target aliases ("aarch64") is not the name the
# NDK uses on disk ("arm64"), so that path just fails.
# openssl's android config sets CROSS_COMPILE=aarch64-linux-android- itself and
# prefixes the tool names with it, so hand it bare ones -- HOSTVARS passes the
# already-prefixed names, which would come out doubled
# (aarch64-linux-android-aarch64-linux-android-ar).
OPENSSL_ENV = ANDROID_NDK_ROOT="$(ANDROID_TOOLCHAIN_PATH)" \
	AR="ar" RANLIB="ranlib" LD="ld" STRIP="strip"

ifeq ($(MY_TARGET_ARCH),arm64-v8a)
OPENSSL_CONFIG_VARS=android-arm64
endif

# no-asm on 32-bit arm for the same reason as iOS armv7 below: openssl's armv7
# assembly does not assemble with clang's integrated assembler (bsaes-armv7.S
# alone trips "immediate operand must be in the range [0,4095]").
ifeq ($(MY_TARGET_ARCH),armeabi-v7a)
OPENSSL_CONFIG_VARS=android-arm
OPENSSL_EXTRA_CONFIG_2=no-asm
endif

ifeq ($(MY_TARGET_ARCH),armeabi)
OPENSSL_CONFIG_VARS=android-arm
OPENSSL_EXTRA_CONFIG_2=no-asm
endif

ifeq ($(MY_TARGET_ARCH),x86)
OPENSSL_CONFIG_VARS=android-x86
endif

# no-asm: openssl's x86_64 assembly now includes AVX-512 code paths that the
# NDK r16 assembler does not know ("instruction requires: AVX-512 BW ISA").
ifeq ($(MY_TARGET_ARCH),x86_64)
OPENSSL_CONFIG_VARS=android-x86_64
OPENSSL_EXTRA_CONFIG_2=no-asm
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
# no-asm: openssl's armv4 assembly emits `.word OPENSSL_armcap_P-.`, which
# clang's integrated assembler rejects for Mach-O ("symbol can not be undefined
# in a subtraction expression"). armv7/armv7s are capped at iOS 10 and long
# discontinued, so dropping to the C implementations there costs nothing that
# matters.
OPENSSL_EXTRA_CONFIG_2=no-async no-asm
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
OPENSSL_EXTRA_CONFIG_2=no-async no-asm
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
	$(MOVE)

.openssl: openssl
	cd $< && $(HOSTVARS_PIC) $(OPENSSL_ENV) ./Configure $(OPENSSL_CONFIG_VARS) --prefix=$(PREFIX) ${OPENSSL_ARCH} $(OPENSSL_EXTRA_CONFIG_1) $(OPENSSL_EXTRA_CONFIG_2)
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
