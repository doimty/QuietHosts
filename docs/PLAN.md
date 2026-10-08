# QuietHosts / 静域 · native implementation plan

## Scope and baseline
Standalone native UIKit app and restricted one-shot helper for iOS 15+ RootHide. Native7 removes the previous Control Center module because it never appeared in Settings. The product has no CCSupport dependency or Control Center toggle. Product name is 静域 / QuietHosts; package `com.doimty.quiethosts`. Native8 builds on native7 (App + helper only). Work stays in this repository on `fix/purple-ui-native8`; install/respring/Hosts changes are separate operations. See `docs/NATIVE8.md` for the current UI scope, failure signals and validation plan.

Frozen dependencies: user's LetMeBlock `1.3.0-1+native1` (3b4057d3e293ca4fc96a7d1bafb29a386a300bb9) and official roothide libSandy `1.1.6-4`; neither is rebuilt or edited. No duplicate DNS tweak. Theos and SDK remain pinned to the last successful Actions build; Apple compilation stays in GitHub Actions.

## Essential product contract
- Three pages: Home (state/count/apply/update), Rules (sources+allowlist), Settings (system/light/dark theme, backup/diagnostics). Purple dynamic palette with pale violet-gray/graphite surfaces, native Dynamic Type/VoiceOver, no animations or fake blocking/battery statistics. Test versions may carry English suffixes such as `+native8`; formal release versions must be numeric-only, pass `validate.py --release`, synchronize App/CI metadata and compare dpkg-newer than the last distributed test package.
- URL/file/paste -> strict parse -> prospective merged preview -> explicit save/apply. Store per-source local snapshots, enabled status and manual refresh; no background domain resolution and no scheduled updates. Accept Hosts blocking-address rows, bare exact domains, and exact-host matchers such as `DOMAIN` and Quantumult X `HOST`; reject non-blocking or unknown policies and never flatten suffix, keyword, IP, URL, or compound match rules into one host.
- Bound each input to16MiB, all local source bytes32MiB, unique merged domains300000, emitted block file32MiB. Overflow rejects whole batch. These are storage safety bounds, not a claim of good device performance at maximum size. Must test actual user files including 206k-domain source-heavy.
- No bundled advertising/certificate-service blocklists. Preserve copyright for borrowed MIT input code; no GPL/unknown-license code copied.

## File ownership / safety
Official RootHide docs explicitly mirror jbroot('/etc/hosts') by symlink to real system file. NEVER open that symlink for writing. LetMeBlock tries managed primary /etc/hosts then /etc/hosts.lmb then real /etc/hosts and caches the managed FILE until process restart.
- Fixed writable target = directory entry jbroot('/etc/hosts'). First activation may take over ONLY an absent entry or a verified symlink referring to real /etc/hosts. Unknown regular target or an existing /etc/hosts.lmb causes explicit conflict, not auto-migration. Package conflicts with CCAdsBeGone variants to avoid competing controllers.
- Save original primary kind and exact symlink text; snapshot original system contents to root-owned state before any overwrite. Generated primary = validated original contents + generated block records, without changing the raw system file. No imported domain may override a preexisting original mapping; reject and report conflicting names or exclude visibly.
- Replace directory entry atomically via sibling file; never follow symlinks. Fixed root-owned helper state under jbroot('/var/lib/quiethosts'), not app-writable. Validate regular files, owners, modes, link counts, bounds. No arbitrary path copy/read/delete API.
- Journal before replacing target; after crash only finish/revert when target matches known before/after fingerprints; otherwise conflict and retain backups. No unverified deletion or rewriting of foreign files. Keep old snapshot for enable, exact baseline restore on disable. Do not change Hosts on install. Uninstall invokes checked restore before removal; stop uninstall on conflict, retain backup state.
- Helper explicit commands status/apply/enable/disable/reload/restore-for-uninstall only. Apply stdin includes prospective canonical blocklist and expected revision; helper revalidates independently. Use revision CAS so preview cannot overwrite concurrent changes. Only uid0/mobile allowed to request bounded fixed operations; package setsroot-owned4755helper with native entitlements. This is a restricted local helper, NOT app-identity authentication.
- Restart only named DNS services after a successful file state change/explicit retry, not on query/status/no-op/failed parse. Wait for command status. UI says files applied / reload requested, never claims all traffic protected. No polling daemon or injection added.
- Native7 is App + helper only. Do not add a Control Center bundle, CCSupport dependency, settings copy or module build target; the module was removed from the product.

## Core interfaces
Shared/QHRuleEngine.h (Foundation): `QHParseResult` exposes canonical domains and statistics. `QHParseRules` parses bounded sources; `QHCompileDomains` merges sources with the exact allowlist and emits canonical Hosts block records. Limits are 16 MiB per input, 32 MiB total source data/output, 32 sources and 300,000 unique domains.

Helper/QHFileManager.h (Foundation): the testable transaction core receives only fixed trusted roots, raw system Hosts path and expected owner; it handles fixed commands and never executes processes. Production helper validates uid/argv, parses bounded stdin, invokes the core and may request only the fixed DNS reload after a successful state change. No arbitrary path or executable API is exposed.

Shared/QHBridge.h: bounded asynchronous bridge used by the App to communicate with the helper. It sanitizes the environment, resolves only the fixed helper path, waits for completion and returns on the main queue. Status queries never reload DNS.

## Validation / independent failure signals
- Pure parser/merge unit tests, malformed encoding, 16MiB/300k/32MiB boundaries, white/black distinction, no DNS calls.
- macOS native helper tests in isolatedtempdirs at currentuid: rawsystemhashunchanged, symlinktakeoverrestore, missingfile, unknownregular/conflicts, secondaryfile, safeowner/symlinkrejection, revisionrace, faultinjection atjournal/rename/statepoints, replay/recovery, no-op, failedwrite, oversized/truncatedrequests. No production helper or system commands executed inhosttests.
- Native UI/bridge compilation + mockhelpertests, localizedplaceholderparity, no secrets inerrors/logs. Realdeb payload/permissions/entitlements/arm64e/min15/dependency/profile/noadditionalDNSinjection checks.
- Actual user corpus read-only hashes before/after and successful parse+generation counts, NOT proofallfiltered.
- Exact GitHubcommit/run/deb hashes and cleanworktree; no successclaim if compilation/runtimefixturemissing. Devicepending: nativeUI/CCregistration, setuidentitlements, filesystemmapping, DNSrestart/cache/filters, energy/stability.
