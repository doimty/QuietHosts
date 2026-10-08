# Native7 · remove the nonfunctional Control Center module

Package candidate: `0.1.0-1+native7`, App + restricted helper only. The user explicitly asked to remove the CC module because it continued not to appear in Settings.

## Removed

- `Module/QuietHostsModule.m`, its Makefile and bundle Info.plist.
- The `Module` target from the Theos aggregate build.
- The `com.opa334.ccsupport` dependency and CC-toggle wording from the package/App UI.
- CC bundle language-resource staging and module-only archive validation.

The standalone app keeps Home, Rules and Settings. Home reports the verified managed Hosts state and the local draft separately, with Apply as the explicit update action. Manual source refresh, checked baseline restore, helper safety and all native5 parser behavior remain.

## Native7 package contract

Only `/Applications/QuietHosts.app`, `/usr/libexec/quiethosts-helper`, documentation and Debian maintainer scripts are expected. No Control Center bundle is built or staged. The App no longer promises a CC toggle. Existing installed CC preferences/configuration are outside package removal scope; this package does not attempt to remove user configuration from the device.

## Validation

Portable helper/parser/localization/directory tests and package source/staging checks are required. macOS Foundation suites, native arm64e/iOS 15 App+helper build, numeric archive ownership and helper `04755` remain CI gates. No device operation is part of the source change.
