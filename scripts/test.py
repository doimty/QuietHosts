import pathlib,subprocess,sys,tempfile,os
ROOT=pathlib.Path(__file__).resolve().parents[1]
def run(args):subprocess.run(args,cwd=ROOT,check=True)
run([sys.executable,'scripts/test_parser.py',*(['--sanitize'] if sys.platform=='darwin' else [])])
run([sys.executable,'scripts/test_regressions.py'])
run([sys.executable,'scripts/check_localization.py'])
run([sys.executable,'scripts/test_directory_policy.py'])
with tempfile.TemporaryDirectory(prefix='qh-process-') as d:
 out=str(pathlib.Path(d)/'test')
 run(['clang','-std=c11','-D_POSIX_C_SOURCE=200809L','-Wall','-Wextra','-Werror','-pthread','Shared/QHProcess.c','Tests/ProcessTests.c','-o',out])
 run([out])
if sys.platform!='darwin':raise SystemExit('Native Foundation suites require macOS + Xcode.')
sources=['Tests/SplitRootTests.m','Shared/QHStatusPresentation.m','Tests/StatusPresentationTests.m','Shared/QHRuleEngine.m','Shared/QHParser.c','Helper/QHFileManager.m','App/QHStore.m','App/QHDownload.m','Tests/FileManagerTests.m','Tests/RuleEngineTests.m','Tests/AppStoreTests.m','App/Tests/QHDownloadTests.m','Tests/main.m']
with tempfile.TemporaryDirectory(prefix='qh-native-') as d:
 out=str(pathlib.Path(d)/'test')
 run(['xcrun','--sdk','macosx','clang','-fobjc-arc','-fblocks','-DQH_TESTING=1','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-framework','Foundation',*sources,'-o',out])
 run([out])
 if os.environ.get('GITHUB_ACTIONS') == 'true':
  # Root only on disposable CI, and only the isolated mixed-UID fixture suite.
  run(['sudo','-n',out,'--mixed-uid'])
