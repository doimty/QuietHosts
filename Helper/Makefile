include $(THEOS)/makefiles/common.mk
TOOL_NAME = quiethosts-helper
quiethosts-helper_FILES = main.m QHDNSReload.c QHFileManager.m ../Shared/QHRuleEngine.m ../Shared/QHParser.c
quiethosts-helper_FRAMEWORKS = Foundation
quiethosts-helper_LIBRARIES = roothide
quiethosts-helper_CFLAGS = -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter -Werror=unguarded-availability
quiethosts-helper_CODESIGN_FLAGS = -SEntitlements.plist
quiethosts-helper_INSTALL_PATH = /usr/libexec
# QH_ROOTLESS_BUILD_BEGIN
ifeq ($(QH_SCHEME),rootless)
quiethosts-helper_LIBRARIES = root
quiethosts-helper_CFLAGS += -DQH_ROOTLESS=1
quiethosts-helper_FILES += QHRootlessLayout.c QHRootlessRouting.c QHRootlessPaths.m
endif
# QH_ROOTLESS_BUILD_END
include $(THEOS_MAKE_PATH)/tool.mk
