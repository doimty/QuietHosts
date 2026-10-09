include $(THEOS)/makefiles/common.mk
APPLICATION_NAME = QuietHosts
QuietHosts_FILES = main.m QHAppDelegate.m QHAppController.m QHVisualComponents.m QHDialogController.m QHStore.m QHDownload.m ../Shared/QHRuleEngine.m ../Shared/QHStatusPresentation.m ../Shared/QHParser.c ../Shared/QHBridge.m ../Shared/QHProcess.c
QuietHosts_FRAMEWORKS = UIKit Foundation UniformTypeIdentifiers CoreGraphics
QuietHosts_LIBRARIES = roothide
QuietHosts_RESOURCE_DIRS = Resources
QuietHosts_CFLAGS = -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter -Werror=unguarded-availability
QuietHosts_CODESIGN_FLAGS = -SEntitlements.plist
QuietHosts_INSTALL_PATH = /Applications
# QH_ROOTLESS_BUILD_BEGIN
ifeq ($(QH_SCHEME),rootless)
QuietHosts_LIBRARIES = root
QuietHosts_CFLAGS += -DQH_ROOTLESS=1
endif
# QH_ROOTLESS_BUILD_END
include $(THEOS_MAKE_PATH)/application.mk
