THEOS_PACKAGE_SCHEME = rootless
TARGET = iphone:clang:15.6:15.0
ARCHS = arm64
include $(THEOS)/makefiles/common.mk
TOOL_NAME = ULPCoverProbe
ULPCoverProbe_FILES = main.m ../../UI/ULPCoverView.m ../../UI/ULPVisualizerView.m ../../Visualization/ULPCover.c ../../Visualization/ULPVisualConfig.c ../../Visualization/ULPWaveform.c ../../Visualization/ULPStyle.c ../../Visualization/ULPTrail.c
ULPCoverProbe_FRAMEWORKS = UIKit QuartzCore CoreGraphics
ULPCoverProbe_CFLAGS = -fobjc-arc -fmodules-cache-path=$(THEOS_PROJECT_DIR)/.theos/module-cache
include $(THEOS_MAKE_PATH)/tool.mk
