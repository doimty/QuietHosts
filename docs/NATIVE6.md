# Native6 UI and copy refinement · local candidate

Candidate version: `0.1.0-1+native6` (build 6), based on native5. Device installation, UI runtime, accessibility and visual acceptance remain pending.

## Reference and design decision

A useful GitHub reference is [SwiftSieve2](https://github.com/shalloran/SwiftSieve2/tree/01ad42c5e1786129d7af872808f1576a1cd1ebd1) (MIT, reviewed at `01ad42c5e1786129d7af872808f1576a1cd1`). Its [HomeView](https://github.com/shalloran/SwiftSieve2/blob/01ad42c5e1786129d7af872808f1576a1cd1/SwiftSieveDNS/Views/HomeView.swift) organizes the app as a native inset-grouped `List`: a compact Status section first, then Block lists and custom domains. The transferable pattern is the information grouping and progressive disclosure, not its DNS-proxy behavior or code. QuietHosts remains UIKit and keeps its existing three tabs/cards.

Native6 applies the pattern within the existing Home screen:

1. A compact status card: icon and state on one row, one explanation, then current managed rule count.
2. A local-draft card: deduplicated domain count, source/allowlist counts, and one sentence saying the draft is local until Apply.
3. One prominent Apply button immediately after the draft.
4. Secondary actions grouped into one card with leading SF Symbols and separators: update online sources (only if enabled URL sources exist), pause/resume managed rules, refresh file status. No lone floating links scattered down the page.
5. A short footer explains update cadence without implementation jargon.

Button rows remain native UIKit `UIButtonConfiguration` controls with Dynamic Type and 44pt minimum height. Card/page insets and vertical gaps are reduced, not removed. Status text now distinguishes “Hosts rules enabled/paused/not applied” from the separate local draft.

## Copy semantics

- “Hosts rules enabled” describes the helper's verified managed-file state, not observed DNS blocking. The explanation says DNS behavior and app caches are not tested.
- “Local rule draft” is explicitly local. The Apply action is the only route that writes a generated list to the managed entry.
- “Current managed rules” and “draft unique domains” are separate counts; source and exact-allowlist counts are labelled independently.
- “Pause rules and restore original Hosts” describes the checked restore operation. “Resume saved rules” explicitly does not apply pending local-draft edits.
- Source refresh copy says online sources update only on request; file/pasted sources must be reimported. No energy/performance promise or fake protection indicator is added.

## Verification boundaries

Portable parser, controller-source, localization, directory-policy and package source gates are still required. A static HTML image is only a hierarchy mock, not a UIKit runtime preview. macOS Foundation tests, Xcode/arm64e build, archive/entitlement audit and actual iOS 15 visual/accessibility checks remain pending until separately authorized to build/install.
