import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
if sys.platform != "darwin":
    print("SKIP: rootless Foundation integration needs macOS + Xcode")
    raise SystemExit(77)

SOURCES = [
    "Tests/RootlessFileManagerTests.m",
    "Helper/QHFileManager.m",
    "Helper/QHRootlessPaths.m",
    "Helper/QHRootlessLayout.c",
    "Helper/QHRootlessRouting.c",
    "Shared/QHRuleEngine.m",
    "Shared/QHParser.c",
]
ROUTING_GUARD = (
    "    const char *routingError = QHRootlessRoutingVerify(&_rootlessRouting);\n"
    "    if (routingError) Fail([NSString stringWithUTF8String:routingError]);\n"
)
MUTATION_FAILURE = "FAIL: rootless dependency alias substitution rejected before target commit"


def build(binary, manager_source=None):
    sources = list(SOURCES)
    if manager_source is not None:
        sources[1] = str(manager_source)
    subprocess.run(
        [
            "xcrun", "--sdk", "macosx", "clang", "-fobjc-arc", "-fblocks",
            "-DQH_ROOTLESS=1", "-DQH_TESTING=1", "-D_DARWIN_C_SOURCE=1",
            "-IHelper", "-IShared", "-Wall", "-Wextra", "-Werror",
            "-framework", "Foundation", *sources, "-o", str(binary),
        ],
        cwd=ROOT,
        check=True,
        timeout=180,
    )


with tempfile.TemporaryDirectory(prefix="qh-rootless-native-") as directory:
    temp = pathlib.Path(directory)
    binary = temp / "test"
    build(binary)
    subprocess.run([str(binary)], cwd=ROOT, check=True, timeout=180)

    # A successful compile is mandatory before interpreting the mutant run.
    manager_text = (ROOT / "Helper/QHFileManager.m").read_text(encoding="utf-8")
    if manager_text.count(ROUTING_GUARD) != 1:
        raise SystemExit("FAIL: expected one per-write rootless routing guard")
    mutant_directory = temp / "Helper"
    mutant_directory.mkdir()
    (temp / "Shared").symlink_to(ROOT / "Shared", target_is_directory=True)
    mutant_source = mutant_directory / "QHFileManager-mutant.m"
    mutant_source.write_text(manager_text.replace(ROUTING_GUARD, "", 1), encoding="utf-8")
    mutant_binary = temp / "test-mutant"
    build(mutant_binary, mutant_source)
    result = subprocess.run(
        [str(mutant_binary), "--routing-guard-mutation"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=180,
    )
    output = result.stdout + result.stderr
    if result.returncode != 1 or MUTATION_FAILURE not in output:
        sys.stderr.write(output)
        raise SystemExit("FAIL: deleting the per-write routing guard was not caught by the focused test")
    print("PASS: prewrite alias test rejects the deleted routing guard")
