TARGET := iphone:clang:latest:16.0
ARCHS = arm64e
include $(THEOS)/makefiles/common.mk
BUNDLE_NAME = iOS2627AnimsPrefs
iOS2627AnimsPrefs_FILES = CG27RootListController.m KeyboardGlassController.m
iOS2627AnimsPrefs_INSTALL_PATH = /Library/PreferenceBundles
iOS2627AnimsPrefs_FRAMEWORKS = UIKit Foundation CoreFoundation
iOS2627AnimsPrefs_PRIVATE_FRAMEWORKS = Preferences
iOS2627AnimsPrefs_LDFLAGS += -F$(THEOS_PROJECT_DIR)/Prefs/linker
iOS2627AnimsPrefs_CFLAGS = -fobjc-arc -Wall -Wextra -fno-ptrauth-objc-class-ro
include $(THEOS_MAKE_PATH)/bundle.mk
