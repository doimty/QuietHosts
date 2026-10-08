# 静域 / QuietHosts

Standalone native UIKit Hosts manager for iOS 15+ RootHide. Current test package candidate: `0.1.0-1+native9`. The Control Center module remains removed; manage QuietHosts from its app. Native9 implements the purple HTML layout as real UIKit: brand/status header, confirmed managed-rules switch, adaptive twin draft metrics, grouped source list/detail, settings sections and tabular preview. See `docs/NATIVE9.md` (current), `docs/NATIVE8.md` (color-only baseline) and `docs/NATIVE7.md` (CC removal). Formal releases must use numeric-only package versions, pass `scripts/validate.py --release` and be dpkg-newer than distributed test packages.

The Home screen separates the verified managed Hosts state from the local rule draft. Importing and editing rules only changes the draft. **Apply draft** explicitly updates the managed Hosts entry; a checked restore returns the saved original state. Online sources update only when requested, while file/pasted sources must be reimported.

## Rule formats

Accept Hosts blocking-address rows, bare exact domains, exact `DOMAIN` rows and Quantumult X exact `HOST` rows. Suffix, keyword, wildcard, IP/CIDR, URL, logical and unknown-policy rules are counted as unsupported rather than flattened to different matching behavior. No bundled lists.

## Dependencies

- `com.ps.letmeblock >=1.3.0-1+native1`
- Official RootHide `com.opa334.libsandy >=1.1.6-4` (not rebuilt)
- `uikittools`

No CCSupport dependency or CC toggle is packaged. QuietHosts conflicts with CCAdsBeGone variants to avoid two managers changing the same Hosts entry; inspect current Hosts before removing either package.

## Hosts safety

RootHide may mirror `/etc/hosts` through a symlink. The helper never writes through that link; it modifies only the verified managed entry. First takeover accepts a verified system mirror, an absent entry, or a basic default Hosts file only after explicit backup-and-adopt confirmation. Unknown regular targets and `hosts.lmb` conflicts are refused. Changes use revision checks, root-owned backup state, a journal and atomic sibling replacement; disable restores the verified original. Unknown/corrupt state is not silently reset. The helper accepts only fixed operations and bounded stdin, not arbitrary paths or executables.

`active` means the managed Hosts file is verified; it does not prove DNS blocking, resolver health, full rule coverage or that app DNS caches are clear. No rules are applied on installation.

## Limits and validation

16 MiB per input, 32 MiB total source data, 32 sources, 300,000 unique domains and 32 MiB generated output. These are safety caps, not performance guarantees. There is no background polling, scheduled download, DNS pre-resolution or VPN behavior. Apple builds run in GitHub Actions on macOS; native Foundation tests require macOS. Portable parser and mock checks use isolated fixtures and never write the real system Hosts file. A passing build is not device acceptance.

See `docs/PLAN.md`, `docs/NATIVE2.md`, `docs/NATIVE4.md` and `docs/file-transactions.md` for the security and recovery details.
