THEOS_PACKAGE_SCHEME = rootless
TARGET = iphone:clang:15.6:15.0
ARCHS = arm64
include $(THEOS)/makefiles/common.mk
TOOL_NAME = ULPCoverPerformance
ULPCoverPerformance_FILES = main.m ../../UI/ULPCoverView.m ../../Visualization/ULPCover.c ../../Visualization/ULPBeat.c ../../Visualization/ULPVisualConfig.c
ULPCoverPerformance_FRAMEWORKS = UIKit QuartzCore CoreGraphics
ULPCoverPerformance_CFLAGS = -fobjc-arc -fmodules-cache-path=$(THEOS_PROJECT_DIR)/.theos/module-cache
include $(THEOS_MAKE_PATH)/tool.mk
