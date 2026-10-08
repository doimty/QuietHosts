# Native5 candidate · exact HOST / CCSupport metadata / compact UI

Package candidate: `0.1.0-1+native5` (arm64e, iOS 15+), based on native4. Device installation, respring and runtime acceptance are separate from this source change and remain pending.

## 1. Exact host-rule conversion range

The existing parser already accepts exact `DOMAIN` rows used by Surge/Loon/Shadowrocket-style lists and Clash rule-provider rows, including bare exact matchers and explicit `REJECT`/`REJECT-DROP`. This change adds the Quantumult X exact `HOST` row shape, with the same hostname canonicalization, allowlist and duplicate pipeline.

Rows with `DIRECT`, proxy/unknown policies, extra options, or non-exact matcher types remain unsupported and are counted. In particular, `DOMAIN-SUFFIX`, `HOST-SUFFIX`, `DOMAIN-KEYWORD`, `HOST-KEYWORD`, IP/CIDR, URL-REGEX, AdGuard filters and logical conditions are not flattened to an exact hostname. A DNS Hosts entry cannot represent their suffix, substring, URL, client, or request-condition semantics. No Blackmatrix rule data or GPL code is copied or bundled; only independently implemented syntax recognition is used, with synthetic fixtures.

Repository syntax survey was checked at Blackmatrix commit [`036c097eb26c6a52c4f04ebcb6633043cb942669`](https://github.com/blackmatrix7/ios_rule_script/tree/036c097eb26c6a52c4f04ebcb6633043cb942669), including [Surge Hijacking](https://github.com/blackmatrix7/ios_rule_script/blob/036c097eb26c6a52c4f04ebcb6633043cb942669/rule/Surge/Hijacking/Hijacking.list), [Clash classical YAML](https://github.com/blackmatrix7/ios_rule_script/blob/036c097eb26c6a52c4f04ebcb6633043cb942669/rule/Clash/Hijacking/Hijacking.yaml), [Loon](https://github.com/blackmatrix7/ios_rule_script/blob/036c097eb26c6a52c4f04ebcb6633043cb942669/rule/Loon/Hijacking/Hijacking.list), [Quantumult X](https://github.com/blackmatrix7/ios_rule_script/blob/036c097eb26c6a52c4f04ebcb6633043cb942669/rule/QuantumultX/Hijacking/Hijacking.list), [Shadowrocket](https://github.com/blackmatrix7/ios_rule_script/blob/036c097eb26c6a52c4f04ebcb6633043cb942669/rule/Shadowrocket/Hijacking/Hijacking.list), and [AdGuard](https://github.com/blackmatrix7/ios_rule_script/blob/036c097eb26c6a52c4f04ebcb6633043cb942669/rule/AdGuard/Advertising/Advertising.txt). The project has distinct client outputs; filename extension alone does not identify a grammar. Its root license is GPL-2.0 and aggregated datasets have separate provenance/redistribution constraints. This candidate does not import or redistribute those datasets.

## 2. Control Center module visibility

Native4's bundled module is already a native `CCUIToggleModule` bundle at `/Library/ControlCenter/Bundles/QuietHostsModule.bundle`; its Info.plist defines the executable, principal class, bundle type and module size. Compared with the CCSupport upstream `CCSupportTemplates` stock Control Center bundle template, the QuietHosts Info.plist lacked `CFBundleSupportedPlatforms` containing `iPhoneOS`. Native5 adds that entry and source/staging validation now checks it and checks that executable/principal class match.

Reference: `https://github.com/opa334/CCSupportTemplates` (`iphone_control_center_module-11up.nic.tar`; the template's `Resources/Info.plist` declares `CFBundleSupportedPlatforms = [iPhoneOS]`). This is a concrete metadata discrepancy and plausible cause, not yet a confirmed device root cause. If the module still does not appear after native5, the remaining checks are actual on-device bundle discovery/cache and CCSupport version/injection, which require device-side evidence after installation. No speculative CCS provider or private hook has been added.

## 3. UI density and theme control

The current theme selector is already Apple's `UISegmentedControl`, not a hand-drawn control. Its stock gray selected segment stood out against the muted teal card theme. Native5 keeps the UIKit segmented control and sets dynamic system colors with teal `selectedSegmentTintColor`, plus readable selected/unselected text. Layout changes are limited to tighter global card/page spacing, margins, corner radius, button inset/typography, and 44-point minimum button/control touch targets. Dynamic Type remains enabled; larger content sizes can still expand the controls.

No custom toggle view or canvas drawing is introduced. Visual impact on real iOS 15 has not been device-validated.

## Verification plan and current boundary

- Portable checks: C parser positive/negative fixtures for exact `HOST`, unsupported actions/suffix/keyword, malformed host names, input limits and existing AdvertisingLite sample parsing.
- Source/package gate: verify CC module `CFBundleSupportedPlatforms`, bundle type, principal class, executable, localized strings, arm64e and iOS 15 minimum.
- Native macOS Actions tests: Foundation rule-engine integration, file manager, mixed UID, archive numeric ownership, helper `04755`, entitlements and final deb hash.
- Device acceptance, only after separately installing the built candidate: check whether QuietHosts appears in Settings → Control Center, add/toggle it, then validate reboot handling. Do not run the production helper or alter Hosts as part of this source-only candidate.
