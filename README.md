# 静域 / QuietHosts

## Native17 UI candidate — not a Havoc release

The isolated `feat/havoc-native17-polish` candidate (`0.1.0-1+native17`, App build17) reworks Home into one verified-file status card and one local-draft workflow, shares appearance tokens across pages/dialogs, distinguishes navigation rows from commands, and adds bilingual first-use/privacy/support guidance. It preserves the restricted helper, explicit confirmation, checked restore and local rule semantics. UI smoke is a single prerequisite job for both package builds; candidate artifacts include the run attempt and upload only after validation succeeds. See [Native17 scope and validation](docs/NATIVE17.md) and [Havoc readiness](docs/HAVOC_READINESS.md). This candidate is for review/testing only, not a paid beta or an already approved store release. Actual cloud and device results must be reported separately.

## Delivered native16 baseline

Standalone native UIKit Hosts manager for iOS 15+. Current cloud-validation candidate: `0.1.0-1+native16` (App build16), with separate RootHide and rootless packages. Native16 fixes the rounded text-field Auto Layout wiring, removes the centered-card scale/spring and commits actual UIKit modal properties before presentation; animated transitions and both input hit areas are now covered by the simulator fixture. See `docs/DIALOG_INPUT_REPAIR.md`. Native15 preserves native14's RootHide alias and uninstall fixes and re-forms short alert confirmations as centered compact cards instead of half-screen bottom sheets; import/URL/diagnostic/option dialogs keep the expanded sheet. See `docs/NATIVE15.md`; cloud and device results must be reported separately. Native14 added brand-derived official RootHide aliases with descriptor target-identity proofs and JSON-pipe checked uninstall input in both schemes. Native13 introduced rootless dynamic-root and dependency-alias validation; rootless device acceptance is still pending. Both build schemes use the same pinned RootHide Theos. See `docs/ROOTLESS_PLAN.md` for scope and test boundaries. The native11 fixes initial dialog height: options, input and paragraph diagnostics open expanded, while short confirmations stay compact. See `docs/DISTRIBUTION_PLAN.md` and `docs/NATIVE10.md`. The Control Center module remains removed; manage QuietHosts from its app. Native9 implements the purple HTML layout as real UIKit: brand/status header, confirmed managed-rules switch, adaptive twin draft metrics, grouped source list/detail, settings sections and tabular preview. See `docs/NATIVE9.md` (current), `docs/NATIVE8.md` (color-only baseline) and `docs/NATIVE7.md` (CC removal). Formal releases must use numeric-only package versions, pass `scripts/validate.py --release` and be dpkg-newer than distributed test packages.

The Home screen separates the verified managed Hosts state from the local rule draft. Importing and editing rules only changes the draft. **Apply draft** explicitly updates the managed Hosts entry; a checked restore returns the saved original state. Online sources update only when requested, while file/pasted sources must be reimported.

## Rule formats

Accept Hosts blocking-address rows, bare exact domains, exact `DOMAIN` rows and Quantumult X exact `HOST` rows. Suffix, keyword, wildcard, IP/CIDR, URL, logical and unknown-policy rules are counted as unsupported rather than flattened to different matching behavior. No bundled lists.

## Dependencies

- `com.ps.letmeblock`
- `com.opa334.libsandy`
- `uikittools`

No CCSupport dependency or CC toggle is packaged. QuietHosts conflicts with CCAdsBeGone variants to avoid two managers changing the same Hosts entry; inspect current Hosts before removing either package.

## Hosts safety

RootHide may mirror `/etc/hosts` through a symlink. The helper never writes through that link; it modifies only the verified managed entry. First takeover accepts a verified system mirror, an absent entry, or a basic default Hosts file only after explicit backup-and-adopt confirmation. Unknown regular targets and `hosts.lmb` conflicts are refused. Changes use revision checks, root-owned backup state, a journal and atomic sibling replacement; disable restores the verified original. Unknown/corrupt state is not silently reset. The helper accepts only fixed operations and bounded stdin, not arbitrary paths or executables.

Rootless validates its libroot-derived physical root against the dependency's `/var/jb` alias before every guarded operation. Its protected directories must belong to root; RootHide's mobile-owned routing exceptions are not reused. Unsupported layouts, foreign `hosts.lmb`, changed aliases and directory substitutions are explicitly refused. See `docs/ROOTLESS_TOOLCHAIN.md` and `docs/ROOTLESS_PLAN.md`.

`active` means the managed Hosts file is verified; it does not prove DNS blocking, resolver health, full rule coverage or that app DNS caches are clear. No rules are applied on installation.

## Limits and validation

16 MiB per input, 32 MiB total source data, 32 sources, 300,000 unique domains and 32 MiB generated output. These are safety caps, not performance guarantees. There is no background polling, scheduled download, DNS pre-resolution or VPN behavior. Apple builds run in GitHub Actions on macOS; native Foundation tests require macOS. Portable parser and mock checks use isolated fixtures and never write the real system Hosts file. A passing build is not device acceptance.

See `docs/PLAN.md`, `docs/NATIVE2.md`, `docs/NATIVE4.md` and `docs/file-transactions.md` for the security and recovery details.
