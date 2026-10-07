# File transaction contract

`Helper/QHFileManager.m` is a testable Foundation/POSIX core. The production main supplies only the mapped jailbreak root, raw `/etc/hosts`, uid0, fixed commands and bounded JSON. The app never supplies a path. Actual DNS restart lives only in main, not the core or native fixtures.

First takeover: primary is absent or a verified symlink to the raw system Hosts; secondary `hosts.lmb` must not exist. Unknown regular files and symlinks to other locations are conflicts. The helper saves an immutable root-owned baseline and the original entry type/link, then overlays canonical validated block pairs while refusing names already present in the baseline. Raw system Hosts is never opened for writing.

Each transaction uses a locked private state directory, inactive snapshot slot, durable original preparation, same-directory staged target, then a journal with before/after file fingerprints. Only after journal persistence may the directory entry change. On recovery, only a verified before/after target and matching journal lineage permit completing the operation; foreign data is not erased. Status can finish a pending transaction but cannot restart DNS. The response reports reloadPending for such recovery; users must explicitly retry reload. Files may be active without DNS caches refreshed, and UI must not equate active with verified network blocking.

Disable restores original absence or the exact symlink text; it does not copy a generic Hosts file into raw `/etc/hosts`. Restore-for-uninstall is root-only, checked and can refuse. Original and snapshot files remain after package removal to prevent silent data loss.

A crash before the first durable journal can leave orphan prepared files. Current candidate refuses them as orphan-preparation rather than guessing ownership/provenance and overwriting the backup. This preserves data but requires diagnostic/manual recovery; do not advertise recovery from every possible failure without intervention. Temporary files are not removed from unknown/foreign conflict states.

Metadata corruption, external changes, unsafe ownership/mode/link count, secondary overlay, lost locks or revision mismatches must fail. This is not a boundary against a root adversary who can rewrite both journal and target. Helper authorization is local uid0/mobile501, not signing-identity authentication.

Native fixture suites create separate mapped/raw trees at current uid, including fake symlinks and deliberate subprocess crashes. They must not compile/run Helper/main.m. Device acceptance remains outstanding for RootHide filesystem permissions, setuid launch, real mirror text and DNS restart behavior.
