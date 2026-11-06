ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WeChatGlass
WeChatGlass_FILES = Tweak.xm
WeChatGlass_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
WeChatGlass_FRAMEWORKS = UIKit Foundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
