TARGET := iphone:clang:10.3:10.0
ARCHS := armv7

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = GarminNativeSender
GarminNativeSender_FILES = main.m AppDelegate.m GNProtocol.m GNTrace.m GNSender.m
GarminNativeSender_FRAMEWORKS = UIKit CoreBluetooth
GarminNativeSender_RESOURCE_DIRS = Resources
GarminNativeSender_CFLAGS = -fobjc-arc -fblocks -Wall -Wextra
GarminNativeSender_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
