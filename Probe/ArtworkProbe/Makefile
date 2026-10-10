THEOS_PACKAGE_SCHEME = rootless
TARGET = iphone:clang:15.6:15.0
ARCHS = arm64
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = ULPArtworkProbe
ULPArtworkProbe_FILES = ArtworkProbe.xm
ULPArtworkProbe_FRAMEWORKS = UIKit ImageIO
ULPArtworkProbe_CFLAGS = -fobjc-arc -fmodules-cache-path=$(THEOS_PROJECT_DIR)/.theos/module-cache
include $(THEOS_MAKE_PATH)/tweak.mk
