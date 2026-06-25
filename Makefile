ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = SpringBoard
THEOS_PACKAGE_SCHEME = rootless
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VCam

VCam_FILES = Tweak.xm MediaManager.m
VCam_CFLAGS = -fobjc-arc
VCam_CXXFLAGS = -fobjc-arc -std=c++17
VCam_LDFLAGS = -std=c++17
VCam_FRAMEWORKS = UIKit AVFoundation CoreMedia CoreVideo CoreImage MobileCoreServices
VCam_PRIVATE_FRAMEWORKS = 

include $(THEOS_MAKE_PATH)/tweak.mk

# SUBPROJECTS += vcamsettings  # Disabled: Preferences.framework not in iOS 16.5 SDK
# include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 SpringBoard"
