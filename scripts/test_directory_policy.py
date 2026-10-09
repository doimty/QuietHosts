#!/usr/bin/env python3
"""Host-only production predicates; no Apple build, root/chown or device access."""
import argparse
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BASE = "60f2a5adf3994f022b422cb643a31d5c2a21eb01"


def baseline_header():
    source = subprocess.check_output(
        ["git", "show", f"{BASE}:Helper/QHFileManager.m"], cwd=ROOT, text=True
    )
    old = re.search(r"static void CheckDir\(.*?\n}\n", source, re.S).group(0)
    condition = re.search(r"if \((.*?)\) \{\s*Fail", old, re.S).group(1)
    # Extract the actual baseline's stat policy, rather than hand-copying it.
    prefix = "fd < 0 || fstat(fd, &s) || "
    assert condition.startswith(prefix)
    condition = condition[len(prefix):]
    assert 'CheckDir(_rootFD, owner, NO);' in source
    assert '_varFD = openat(_rootFD, "var", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);' in source
    return (
        "static inline int QHBaselineRootAllowed(const struct stat *p, uid_t owner) {\n"
        "    struct stat s = *p; int privateDir = 0;\n"
        f"    return !({condition});\n}}\n"
    )


def check_platform_alias_contract():
    platform = (ROOT / "Shared/QHPlatform.h").read_text(encoding="utf-8")
    rootless = platform.split("#if defined(QH_ROOTLESS) && QH_ROOTLESS", 1)[1].split("#else", 1)[0]
    assert "<rootless.h>" in rootless
    assert "rootfs" not in rootless.lower() and "roothide" not in rootless.lower()
    assert "rootfs(path.fileSystemRepresentation)" in platform
    assert '"/rootfs/' not in platform, "RootHide alias must come from rootfs(), not a prefix rule"

    policy = (ROOT / "Helper/QHDirectoryPolicy.h").read_text(encoding="utf-8")
    candidate = policy.split("/* QH_ROOTHIDE_ROOTFS_ALIAS_BEGIN", 1)[1].split(
        "/* QH_ROOTHIDE_ROOTFS_ALIAS_END */", 1
    )[0]
    assert "QHPlatformRootFSPath(native)" in candidate
    assert "QHBrandedRootFSDataAliasAllowed" in candidate
    assert "realpath(nativePath, resolved)" in candidate
    assert "#if defined(__OBJC__) && !(defined(QH_ROOTLESS) && QH_ROOTLESS)" in candidate
    print("PASS: exact RootHide alias contract; rootless branch has no roothide/rootfs reference")


def main():
    check_platform_alias_contract()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-baseline", action="store_true",
                        help="also prove original guards fail; requires base commit in local history")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="qh-policy-build-") as directory:
        tmp = Path(directory)
        common = shlex.split(os.environ.get("CC", "cc")) + [
            "-std=c11", "-D_DEFAULT_SOURCE", "-Wall", "-Wextra", "-Werror",
            "-I", str(tmp), str(ROOT / "Tests/DirectoryPolicyTests.c")
        ]
        subprocess.run(common + ["-o", str(tmp / "policy")], check=True)
        subprocess.run([str(tmp / "policy")], check=True)
        if args.check_baseline:
            (tmp / "baseline_policy.h").write_text(baseline_header())
            subprocess.run(common + ["-DQH_BASELINE_POLICY", "-o", str(tmp / "baseline")], check=True)
            negative = subprocess.run([str(tmp / "baseline")], capture_output=True, text=True)
            assert negative.returncode == 1, negative.stdout + negative.stderr
            assert negative.stderr.splitlines() == ["FAIL: container root uid501 allowed"] + [
                "FAIL: root unsafe mode rejected"
            ] * 3, negative.stderr
            print("Baseline negative control: actual CheckDir fails uid501 and three special-bit regressions")
        print("Baseline var O_NOFOLLOW rejection proven by isolated host syscall, not native execution")
        print("PASS: production directory policy; native Foundation/device acceptance still pending")


if __name__ == "__main__":
    main()
