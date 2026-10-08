# Native roothide candidate; do not package rootless compatibility shims.
THEOS_PACKAGE_SCHEME = roothide
export TARGET = iphone:clang:16.5:15.0
export ARCHS = arm64e
export FINALPACKAGE = 1
include $(THEOS)/makefiles/common.mk
# native7 intentionally packages only the standalone App and helper.
SUBPROJECTS = App Helper
include $(THEOS_MAKE_PATH)/aggregate.mk
before-package::
	python3 scripts/stage.py --stage "$(THEOS_STAGING_DIR)"
after-package::
	python3 scripts/validate.py --stage "$(THEOS_STAGING_DIR)"
