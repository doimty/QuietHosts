# Native4 candidate · reboot-safe persisted fingerprints

Package: `0.1.0-1+native4` (arm64e, iOS 15+). This candidate preserves native3's DNS reload, exact Surge `DOMAIN` conversion and document-picker cancellation fixes.

## Incident and root cause

After a phone reboot, the installed native3 app reported `target-conflict`. Read-only root evidence showed:

- current managed Hosts and persisted `state.json` target had the same SHA-256, inode, owner/group, mode, size, link count and nanosecond modification time;
- current target `st_dev` was `16777218`, while the persisted target had `16777223`;
- raw system Hosts and its persisted system fingerprint were unchanged;
- no `journal.json` was present, and the exact 213-byte baseline backup remained intact.

The failure was therefore a false conflict from treating Darwin's mount-instance device number as a reboot-stable file identity.

## Fix

`SamePersistedTarget` is used only when comparing a freshly observed fingerprint with persisted state/journal fingerprints across requests or recovery. It ignores `st_dev` but retains exact kind, content hash or symlink text, inode, uid, gid, mode, size, link count, and nanosecond mtime. Missing entries still require an exact missing fingerprint. Live same-request guards and namespace directory anchors remain strict; this does not weaken rename, symlink, ownership, content, or transaction checks.

The helper does not rewrite or delete existing state merely because the device number changed. State and backups remain root-owned and are still validated before any write.

## Regression coverage

Foundation fixtures cover an active state with a changed persisted `st_dev`, subsequent apply and exact disable restore, plus journal recovery at `after-journal` and `after-rename-before-sync` with the same simulated mount identity change. Existing corruption, ownership, race, crash-recovery, mixed-UID, parser, localization and package checks remain in the CI gate.

This candidate has not been installed or tested through a real reboot yet. Device Hosts, journal and baseline were read only; no forced overwrite, state deletion, DNS signal or SpringBoard restart was performed during diagnosis.
