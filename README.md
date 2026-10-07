# 静域 / QuietHosts

Native UIKit Hosts source manager for iOS 15+ RootHide. Candidate `0.1.0-1+native4`; installation and device behavior still require separate acceptance.

Native4 fixes a reboot false-positive: persisted fingerprint checks no longer treat Darwin's mount-instance `st_dev` as a durable file identity, while content hash, inode, ownership, mode, size, link count and nanosecond timestamps remain strict. It also retains native3's DNS reload child credentials, exact Surge `DOMAIN` conversion, and document-picker gesture-dismissal cancellation. See `docs/NATIVE4.md` for scope and validation boundaries.

Native2 adapts the verified split-root layout: primary root and paired routing var may be UID501, protected etc/private/paired-root/lib/state must retain the expected root ownership. Paired paths and backlink are independently derived and checked, not arbitrary symlink targets. Only a regular file containing the three conventional localhost/broadcasthost mappings becomes eligible for **explicit backup-and-adopt confirmation**; its exact original bytes, owner/group and mode are restored on Disable. Other regular files remain conflicts. Error codes are shown on Home, error dialogs and Advanced information.

Directory FDs and routing timestamps detect namespace changes, including move-away/move-back, but do not make check-plus-write atomic. A last-check race can change the known protected target before a subsequent guard detects the race; tests assert failure with retained journal/backup, not a false zero-write guarantee. See `docs/NATIVE2.md`.

Three pages: Home, Rules, Settings. Muted teal/warm-white/graphite design; system/light/dark themes; no fake statistics. Local/URL/pasted Hosts and bare-domain sources, exact allowlist, preview before source changes, then separate checked Apply. Manual URL updates are all-or-nothing; no periodic downloads, per-domain DNS pre-resolution, VPN, or extra DNS hooks.

## Dependencies
- `com.ps.letmeblock >=1.3.0-1+native1` from our native build.
- Official RootHide `com.opa334.libsandy >=1.1.6-4` **unchanged**, plus CCSupport and uikittools.
- No dependency binaries packaged in this project. CCAdsBeGone conflicts prevent two independent managers; uninstalling that package has its own restore behavior, so inspect your current Hosts first.

## Safety
RootHide's `/etc/hosts` directory entry may be a system-file mirror symlink. The helper will not write through it. First takeover accepts a verified system mirror or absent entry, or a verified basic regular file only after explicit adoption consent; it refuses other regular targets and any secondary `hosts.lmb`. It keeps a root-owned baseline, validates generated contents, checks revision/fingerprints, uses a durable journal and atomic sibling replacement, restores the original entry on Disable, and refuses foreign-file conflicts. Backup state is retained on uninstall. Unknown/corrupt state is not silently reset.

The App runs as the ordinary mobile user. The restricted helper is root-owned/setuid, accepts only fixed commands and input through bounded stdin; no arbitrary file path or executable API. This is local uid-based authorization, **not cryptographic authentication of only our app**. A privileged/root compromise is outside the claimed boundary.

`active` reports verified on-disk file state. Restarting mDNSResponder is requested only after a changed transaction or explicit retry, and does not prove resolver health, domain coverage, or battery benefit. Existing admitted connections and application caches may remain. System private APIs, RootHide mapping and setuid behavior must be validated on-device.

## Limits
16MiB per source,32MiB total raw local data,32 sources,300000 unique merged domains and32MiB generated output (including baseline at apply). Paste editor64KiB; use files for larger lists. These are defensive storage limits, not a promise of good performance at maximum size. Hosts supports exact names, not arbitrary wildcard/subdomain/suffix/keyword/path matching. Redirect mappings, local names and unsupported syntax are counted; allowlist invalid entries reject the batch. No built-in certificate-service blocklists.

## Build and test
GitHub Actions on macOS with fixed RootHide Theos and SDK. No local Apple cross-compile required. `python3 scripts/test.py` runs actual native fixture tests on macOS only and portable C tests; `python3 scripts/test_parser.py` and process transport tests are host-portable. Tests use temporary trees, never real `/etc/hosts`, and never run the production privileged helper.

See `docs/PLAN.md` and `docs/file-transactions.md` for the first-version contract. Do not install an unvalidated artifact merely because the build succeeded; review the build/test receipt and independent package checks first.
