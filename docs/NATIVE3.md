# Native3 candidate · 修复范围与验收边界

Package: `0.1.0-1+native3` (arm64e, iOS 15+). This candidate builds on the delivered native2 tree; it does not change or rebuild LetMeBlock, libSandy, RootHide mappings, or the device's current Hosts file.

## Changes

1. **DNS reload credentials and diagnosis.** `QHDNSReload` executes only the existing fixed `/usr/bin/killall -9 mDNSResponder mDNSResponderHelper` argv and fixed minimal environment. The helper parent remains mobile-real/root-effective; only the forked, time-bounded child normalizes supplementary groups and UID/GID to root so Apple's `killall` UID filtering can find the DNS daemon. The parent's child tracking, wait and timeout remain bounded. Result stage/errno/exit/signal are converted to stable, sanitized error codes; UI displays a bilingual diagnostic. A reload failure does not roll back already committed files or claim filtering is active.
2. **Surge block-rule conversion.** Parse exact `DOMAIN,name` and exact `DOMAIN,name,REJECT|REJECT-DROP` records into the existing canonical domain pipeline. Normal validation, lowercasing, exact allowlist and deduplication still apply. Unsupported actions/options and suffix, keyword, IP-range and URL rules are counted and not flattened into different semantics.
3. **Document-picker cancellation.** Observe adaptive presentation dismissal in addition to the picker cancel delegate. A main-thread lifecycle token binds callbacks to the current picker and separates picker dismissal from the selected-file read. Duplicate/stale cancel or selection callbacks cannot unlock a newer operation; a normal user cancellation clears the busy state. Successful selection continues reading off-main and remains busy until completion.

## Validation in this change

- `scripts/test_regressions.py`: lifecycle model tests; the actual fixed DNS runner exercised only against synthetic mock executables (no DNS service is signalled); source integration assertions. Root-credential fixture checks the child, fixed argv/environment, parent identity preservation, failure/wait/timeout paths.
- `scripts/test_parser.py` with the real AdvertisingLite sample: exact DOMAIN conversion, rejection/counting of unsupported rule semantics, parser limits and sanitizer builds where available.
- `scripts/check_localization.py`: English/Chinese resource parity and every `QHL` literal.
- `scripts/test.py`, macOS Foundation fixtures, Theos/Xcode arm64e build, signed entitlements, numeric package ownership and real `.deb` checks remain required in GitHub Actions.

These are host/CI checks, **not** proof of the iOS 15 document-picker callback behavior or real mDNSResponder restart. No Frida instrumentation, device installation, system file mutation or DNS signal is part of this candidate. Review the exact Actions run and artifact before any separately authorized device acceptance.
