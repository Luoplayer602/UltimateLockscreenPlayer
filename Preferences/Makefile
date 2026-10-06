THEOS_PACKAGE_SCHEME = rootless
TARGET = iphone:clang:15.6:15.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ULPPreferences
ULPPreferences_FILES = ULPRootListController.m
ULPPreferences_FRAMEWORKS = UIKit
ULPPreferences_PRIVATE_FRAMEWORKS = Preferences
ULPPreferences_INSTALL_PATH = /Library/PreferenceBundles
ULPPreferences_CFLAGS = -fobjc-arc -fmodules-cache-path=$(THEOS_PROJECT_DIR)/.theos/module-cache

include $(THEOS_MAKE_PATH)/bundle.mk
