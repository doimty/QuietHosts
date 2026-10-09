# Explicit package environment; never use rootless compatibility shims.
export QH_SCHEME ?= roothide
ifeq ($(QH_SCHEME),roothide)
THEOS_PACKAGE_SCHEME = roothide
export ARCHS = arm64e
else ifeq ($(QH_SCHEME),rootless)
THEOS_PACKAGE_SCHEME = rootless
export ARCHS = arm64
THEOS_LAYOUT_DIR_NAME = layout-rootless
else
$(error Unsupported QH_SCHEME: $(QH_SCHEME))
endif
export TARGET = iphone:clang:16.5:15.0
export FINALPACKAGE = 1
include $(THEOS)/makefiles/common.mk
# native7 intentionally packages only the standalone App and helper.
SUBPROJECTS = App Helper
include $(THEOS_MAKE_PATH)/aggregate.mk
before-package::
	python3 scripts/stage.py --stage "$(THEOS_STAGING_DIR)"
after-package::
	python3 scripts/validate.py --stage "$(THEOS_STAGING_DIR)" --scheme "$(QH_SCHEME)"
