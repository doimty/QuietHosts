include $(THEOS)/makefiles/common.mk
BUNDLE_NAME = QuietHostsModule
QuietHostsModule_FILES = QuietHostsModule.m ../Shared/QHBridge.m ../Shared/QHProcess.c
QuietHostsModule_FRAMEWORKS = UIKit Foundation
QuietHostsModule_PRIVATE_FRAMEWORKS = ControlCenterUIKit
QuietHostsModule_LIBRARIES = roothide
QuietHostsModule_RESOURCE_DIRS = Resources
QuietHostsModule_CFLAGS = -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter -Werror=unguarded-availability
QuietHostsModule_INSTALL_PATH = /Library/ControlCenter/Bundles
include $(THEOS_MAKE_PATH)/bundle.mk
