THEOS_PACKAGE_SCHEME = rootless
TARGET = iphone:clang:15.6:15.0
ARCHS = arm64
INSTALL_TARGET_PROCESSES = mediaserverd

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AudioSnapshotServer
AudioSnapshotServer_FILES = Tweak.cpp CaptureEngine.cpp FeatureAnalyzer.cpp FeatureServer.cpp
AudioSnapshotServer_FRAMEWORKS = AudioToolbox Accelerate
AudioSnapshotServer_LIBRARIES = substrate
AudioSnapshotServer_CCFLAGS = -std=c++17 -fblocks -O3 -fmodules-cache-path=$(THEOS_PROJECT_DIR)/.theos/module-cache

include $(THEOS_MAKE_PATH)/tweak.mk
