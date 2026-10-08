# QuietHosts working rules

- Native roothide only, iOS15+ first candidate. Read docs/PLAN.md before nontrivial changes.
- Only this repository; do not modify/rebuild LetMeBlock, libSandy, NetShield2, user mounts or design artifacts.
- No device commands, installation, restarts, writing real /etc/hosts, or executing third-party scripts. Tests must use isolated temporary fixtures. All Apple compilation through GitHub Actions, not local cross-compilation.
- RootHide mirrors /etc/hosts: never write through symlinks. Helper only fixed destination/root-owned state and exact allowlisted commands; no arbitrary path arguments. Unknown state/path/ownership/conflicting files -> explicit refusal. Crash recovery must preserve original and foreign content.
- No DNS pre-resolution, polling daemon, periodic downloads, VPN, unrelated hooks, telemetry, built-in blocklists or false protection/energy counters.
- API signatures in docs/PLAN.md are shared agent contracts; coordinate changes before editing another owner's files. All text Chinese-first/English fallback using QHL lookup.
- Native tests and static checks must distinguish code/model checks from actual device validation. No warning suppression or test bypass to hide defects. Native7 is App + helper only; do not retain or rebuild the removed Control Center module.
- Preserve MIT notices for reused upstream code. No copying from GPL/source-visible-only references into this MIT project.
- Initial work/new branch feat/native-app. Only parent may create commits/push/CI. Never push main/default or publish an APT repository.
