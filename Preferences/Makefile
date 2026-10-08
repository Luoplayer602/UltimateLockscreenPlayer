THEOS_PACKAGE_SCHEME = rootless
TARGET = iphone:clang:15.6:15.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ULPPreferences
PREVIEW_AUDIO = $(THEOS_PROJECT_DIR)/demo-ui/audio/inst.wav
ifeq ($(wildcard $(PREVIEW_AUDIO)),)
$(error Thiếu $(PREVIEW_AUDIO): cần tệp nhạc mẫu để build Preview)
endif

ULPPreferences_FILES = ULPSettingsListController.m ULPRootListController.m ULPVisualizerListController.m ULPModePickerController.m ULPLabeledSliderCell.m ULPVisualizerPreviewController.m ../UI/ULPVisualizerView.m ../Visualization/ULPVisualConfig.c ../Visualization/ULPVisualPreferences.m ../Visualization/ULPSignal.c
ULPPreferences_RESOURCE_FILES = $(PREVIEW_AUDIO)
ULPPreferences_FRAMEWORKS = UIKit AVFoundation
ULPPreferences_PRIVATE_FRAMEWORKS = Preferences
ULPPreferences_INSTALL_PATH = /Library/PreferenceBundles
ULPPreferences_CFLAGS = -fobjc-arc -fmodules-cache-path=$(THEOS_PROJECT_DIR)/.theos/module-cache

include $(THEOS_MAKE_PATH)/bundle.mk
