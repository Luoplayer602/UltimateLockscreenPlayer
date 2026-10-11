THEOS_PACKAGE_SCHEME = rootless
TARGET = iphone:clang:15.6:15.0
ARCHS = arm64
include $(THEOS)/makefiles/common.mk
TOOL_NAME = ULPBeatProbe
ULPBeatProbe_FILES = main.m ../../UI/ULPVisualizerView.m ../../UI/ULPCoverView.m ../../Visualization/ULPCover.c ../../Visualization/ULPBeat.c ../../Visualization/ULPVisualConfig.c ../../Visualization/ULPWaveform.c ../../Visualization/ULPStyle.c ../../Visualization/ULPTrail.c ../../Audio/ULPPreviewSpectrum.c
ULPBeatProbe_FRAMEWORKS = UIKit QuartzCore CoreGraphics AVFoundation
ULPBeatProbe_CFLAGS = -fobjc-arc -fmodules-cache-path=$(THEOS_PROJECT_DIR)/.theos/module-cache
include $(THEOS_MAKE_PATH)/tool.mk
