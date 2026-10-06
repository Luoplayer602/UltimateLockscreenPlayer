THEOS_PACKAGE_SCHEME = rootless
TARGET = iphone:clang:15.6:15.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TOOL_NAME = ulp-msh2-probe
ulp-msh2-probe_FILES = main.c ../Audio/MSH2Protocol.c
ulp-msh2-probe_CFLAGS = -O2 -Wall -Wextra -fmodules-cache-path=$(THEOS_PROJECT_DIR)/.theos/module-cache

include $(THEOS_MAKE_PATH)/tool.mk
