THEOS_PACKAGE_SCHEME = rootless
TARGET = iphone:clang:15.6:15.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = UltimateLockscreenPlayer
UltimateLockscreenPlayer_FILES = Tweak.xm Audio/MSH2Protocol.c Audio/MSH2Client.m Playback/ULPLifecycle.c Playback/ULPNowPlaying.m Playback/ULPProgressClock.c Visualization/ULPSignal.c UI/ULPLockScreenView.m UI/ULPVisualizerView.m UI/ULPBackgroundView.m
UltimateLockscreenPlayer_CFLAGS = -fobjc-arc -fmodules-cache-path=$(THEOS_PROJECT_DIR)/.theos/module-cache
UltimateLockscreenPlayer_FRAMEWORKS = UIKit CoreImage

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
