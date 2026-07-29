TARGET := iphone:clang:10.3:10.0
ARCHS := armv7

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := GarminConnectBypass
GarminConnectBypass_FILES := Tweak.m
GarminConnectBypass_CFLAGS := -fobjc-arc
GarminConnectBypass_FRAMEWORKS := Foundation UIKit CoreBluetooth QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
