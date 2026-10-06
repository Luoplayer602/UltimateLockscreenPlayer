THEOS_PACKAGE_SCHEME = rootless
TARGET = iphone:clang:15.6:15.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ULPMediaViewProbe
ULPMediaViewProbe_FILES = MediaViewProbe.xm
ULPMediaViewProbe_CFLAGS = -fobjc-arc -fmodules-cache-path=$(THEOS_PROJECT_DIR)/.theos/module-cache

include $(THEOS_MAKE_PATH)/tweak.mk
