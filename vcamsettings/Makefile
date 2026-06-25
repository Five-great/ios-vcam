ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = VCamSettings

VCamSettings_FILES = VCamRootListController.m
VCamSettings_INSTALL_PATH = /Library/PreferenceBundles
VCamSettings_FRAMEWORKS = UIKit
VCamSettings_PRIVATE_FRAMEWORKS = Preferences
VCamSettings_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/VCam.plist$(ECHO_END)
