THEOS_PACKAGE_SCHEME = rootless
TARGET = iphone:clang:15.6:15.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ULPServerProbe
ULPServerProbe_FILES = ServerProbe.mm
ULPServerProbe_FRAMEWORKS = AudioToolbox
ULPServerProbe_CFLAGS = -fobjc-arc -fblocks -fmodules-cache-path=$(THEOS_PROJECT_DIR)/.theos/module-cache
ULPServerProbe_CCFLAGS = -std=c++17

include $(THEOS_MAKE_PATH)/tweak.mk
