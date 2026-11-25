TARGET := iphone:clang:latest:15.0
ARCHS = arm64e
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = iOS2627Anims
SWITCH_DIR = SwitchFeature
iOS2627Anims_FILES = Tweak.x $(SWITCH_DIR)/src/NGSwitch.m $(SWITCH_DIR)/src/NGResources.m $(SWITCH_DIR)/src/Tweak.m
iOS2627Anims_SWIFT_FILES = $(shell find $(SWITCH_DIR)/Vendor/Theseus/Sources/Theseus -type f -name '*.swift' -print | sort) $(SWITCH_DIR)/src/TheseusBridge.swift $(SWITCH_DIR)/src/TheseusBundle.swift
# Older libobjc runtimes cannot load signed class_ro pointers from new clang.
iOS2627Anims_CFLAGS = -fobjc-arc -Wall -Wextra -fno-ptrauth-objc-class-ro
iOS2627Anims_FRAMEWORKS = UIKit QuartzCore CoreGraphics Metal MetalKit CoreVideo IOSurface Accelerate
iOS2627Anims_SWIFT_VERSION = 5
iOS2627Anims_SWIFT_BRIDGING_HEADER = iOS2627Anims-Bridging-Header.h
include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += Prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
