# luajit

LUAJIT_VERSION := 2.1
# luajit.org's download server is gone; LuaJIT 2.1 has never had a final
# tagged release, so pull the same rolling v2.1 branch from GitHub instead.
LUAJIT_URL := https://codeload.github.com/LuaJIT/LuaJIT/tar.gz/refs/heads/v2.1

$(TARBALLS)/LuaJIT-$(LUAJIT_VERSION).tar.gz:
	$(call download,$(LUAJIT_URL))

.sum-luajit: LuaJIT-$(LUAJIT_VERSION).tar.gz

luajit: LuaJIT-$(LUAJIT_VERSION).tar.gz .sum-luajit
	$(UNPACK)
ifeq ($(LUAJIT_VERSION),2.0.1)
	$(APPLY) $(SRC)/luajit/v2.0.1_hotfix1.patch
endif

ifeq ($(LUAJIT_VERSION),2.1.0-beta2)
	$(APPLY) $(SRC)/luajit/luajit-v2.1.0-beta2.patch
endif
ifeq ($(LUAJIT_VERSION),2.1)
	$(APPLY) $(SRC)/luajit/luajit-v2.1.0-beta3.patch
endif
	$(MOVE)

ifdef HAVE_IOS
# LUAJIT_HOST_CC builds minilua/buildvm, native HOST-side tools that generate
# bytecode for the cross target - they run on this build machine, not on
# iOS, so none of the target arch's flags apply. The old per-arch "gcc -m32"/
# "-m64" dispatch (plus a literal "CC" typo for armv7) targeted 32-bit-vs-
# 64-bit Intel host Macs; on an arm64 host none of that is meaningful, and
# -m32/-m64 aren't valid clang flags here at all, so just use a plain
# native compiler unconditionally.
LUAJIT_HOST_CC="xcrun clang $(OPTIM)"

# LuaJIT's own LJ_NO_SYSTEM auto-detection (lj_arch.h) only fires when the
# deployment target is >= iOS 8.0; our -miphoneos-version-min=7.0 floor
# means it never trips even though system() is unconditionally unavailable
# on current SDKs, so force it directly instead of relying on that check.
# -DLUAJIT_ENABLE_GC64 lives in here (rather than appended at the call site)
# because this value is already a fully-quoted string; wrapping it in a
# second pair of quotes at the call site nests quote characters inside the
# shell word and breaks argument splitting. 32-bit device arches
# (armv7/armv7s) aren't routed through here (see top-level docs), so GC64,
# a 64-bit-only feature, is always safe to force.
LUAJIT_TARGET_FLAGS="-isysroot $(IOS_SDK) -Qunused-arguments -DLJ_NO_SYSTEM=1 -DLUAJIT_ENABLE_GC64 $(EXTRA_CFLAGS) $(EXTRA_LDFLAGS) $(ENABLE_BITCODE)"
LUAJIT_CROSS_HOST=$(xcrun cc)
endif #endof HAVE_IOS

ifdef HAVE_ANDROID

ifeq ($(MY_TARGET_ARCH),armeabi)
LUAJIT_HOST_CC="gcc -m32 $(OPTIM)"
endif

ifeq ($(MY_TARGET_ARCH),armeabi-v7a)
LUAJIT_HOST_CC="gcc -m32 $(OPTIM)"
endif

ifeq ($(MY_TARGET_ARCH),arm64-v8a)
LUAJIT_HOST_CC="gcc -m64 $(OPTIM)"
endif

ifeq ($(MY_TARGET_ARCH),x86)
LUAJIT_HOST_CC="gcc -m32 $(OPTIM)"
endif

ifeq ($(MY_TARGET_ARCH),x86_64)
LUAJIT_HOST_CC="gcc -m64 $(OPTIM) -DLUAJIT_ENABLE_GC64"
endif

LUAJIT_TARGET_FLAGS="${EXTRA_CFLAGS} ${EXTRA_LDFLAGS}"
LUAJIT_CROSS_HOST=$(HOST)-
endif # endof HAVE_ANDROID

ifdef HAVE_MACOSX

ifeq ($(MY_TARGET_ARCH),x86_64)
LUAJIT_HOST_CC="gcc -m64 $(OPTIM)"
# -arch x86_64 for the same reason the arm64 branch below names its target:
# without it LuaJIT builds for whatever the host is, so on an Apple Silicon
# machine the x86_64 slice came out arm64 and lipo refused to pair them.
LUAJIT_TARGET_FLAGS="-DLUAJIT_ENABLE_GC64 -arch x86_64"
endif

ifeq ($(MY_TARGET_ARCH),i386)
LUAJIT_HOST_CC="gcc -m32 $(OPTIM)"
LUAJIT_TARGET_FLAGS=
endif

ifeq ($(MY_TARGET_ARCH),arm64)
LUAJIT_HOST_CC="gcc -m64 $(OPTIM)"
LUAJIT_TARGET_FLAGS="-DLUAJIT_ENABLE_GC64 -target arm64-apple-macos11"
endif

endif # endof HAVE_MACOSX

.luajit: luajit
ifdef HAVE_ANDROID
	cd $< && $(MAKE) -j8 HOST_CC=$(LUAJIT_HOST_CC) CROSS=$(LUAJIT_CROSS_HOST) CC=clang TARGET_SYS=Linux TARGET_FLAGS=$(LUAJIT_TARGET_FLAGS)
endif

ifdef HAVE_MACOSX

	cd $< && $(MAKE) -j8 HOST_CC=$(LUAJIT_HOST_CC) TARGET_FLAGS=$(LUAJIT_TARGET_FLAGS) MACOSX_DEPLOYMENT_TARGET=10.14

endif

ifndef HAVE_ANDROID

ifdef HAVE_LINUX

ifeq ($(MY_TARGET_ARCH),x86_64)
	cd $< && $(HOSTVARS_PIC) $(MAKE) -j8 HOST_CC="$(CC)" HOST_CFLAGS="$(CFLAGS)"
else
	cd $< && $(HOSTVARS_PIC) $(MAKE) -j8 HOST_CC="$(CC) -m32" HOST_CFLAGS="$(CFLAGS)"
endif

endif #ifdef HAVE_LINUX

endif #ifndef HAVE_ANDROID

ifdef HAVE_IOS

# The old x86_64 branch here built as generic Darwin without an explicit
# CROSS/-arch, which just built for the ambient host arch via uname - fine
# on an Intel Mac, but on Apple Silicon that silently produces an arm64
# binary mislabeled as the x86_64 simulator slice. Route every arch through
# the same explicit cross path; LUAJIT_TARGET_FLAGS already carries the
# correct -arch/-isysroot from EXTRA_CFLAGS for whichever arch is active.
	cd $< && $(MAKE) -j8 HOST_CC=$(LUAJIT_HOST_CC) CROSS=$(LUAJIT_CROSS_HOST) TARGET_SYS=iOS TARGET_FLAGS=$(LUAJIT_TARGET_FLAGS)

endif
	cd $< && $(MAKE) install PREFIX=$(PREFIX)
	touch $@
