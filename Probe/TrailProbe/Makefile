THEOS_PACKAGE_SCHEME = rootless
TARGET = iphone:clang:15.6:15.0
ARCHS = arm64
include $(THEOS)/makefiles/common.mk

TOOL_NAME = ULPTrailProbe
ULPTrailProbe_FILES = main.m ../../UI/ULPVisualizerView.m ../../Visualization/ULPVisualConfig.c ../../Visualization/ULPVisualPreferences.m ../../Visualization/ULPWaveform.c ../../Visualization/ULPStyle.c ../../Visualization/ULPTrail.c ../../Audio/ULPPreviewSpectrum.c
ULPTrailProbe_FRAMEWORKS = UIKit QuartzCore CoreGraphics AVFoundation
ULPTrailProbe_FILES += ../../Visualization/ULPCover.c ../../UI/ULPCoverView.m
ULPTrailProbe_CFLAGS = -fobjc-arc -fmodules-cache-path=$(THEOS_PROJECT_DIR)/.theos/module-cache
include $(THEOS_MAKE_PATH)/tool.mk
