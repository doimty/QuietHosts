import argparse, pathlib,plistlib,stat,struct,sys,re
ROOT=pathlib.Path(__file__).resolve().parents[1]
from check_localization import check as check_locale

def require(value,message):
 if not value:raise ValueError(message)
def plist(path):return plistlib.loads(path.read_bytes())
def macho(path):
 raw=path.read_bytes();require(len(raw)>=32 and raw[:4]==b'\xcf\xfa\xed\xfe','Expected thin Mach-O')
 _,cpu,subtype,kind,count,size,_,_=struct.unpack_from('<8I',raw)
 require(cpu==0x100000c and subtype&0xffffff==2,'Expected arm64e');end=32+size;pos=32;minimum=None;signed=False;deps=[]
 for _ in range(count):
  require(pos+8<=end,'Bad command area');cmd,n=struct.unpack_from('<II',raw,pos);require(n>=8 and pos+n<=end,'Bad command')
  if cmd==0x32:platform,v,sdk=struct.unpack_from('<III',raw,pos+8);require(platform==2,'Not iOS');minimum=v
  if cmd==0x25:minimum=struct.unpack_from('<I',raw,pos+8)[0]
  if cmd==0x1d:
   offset,length=struct.unpack_from('<II',raw,pos+8);require(length>0 and offset+length<=len(raw),'Bad signature');signed=True
  if cmd in (0xc,0x80000018):
   offset=struct.unpack_from('<I',raw,pos+8)[0];deps.append(raw[pos+offset:pos+n].split(b'\0')[0].decode())
  pos+=n
 require(minimum==15<<16 and signed and pos==end,'Missing minOS/signature')
 require(not any('/var/jb' in x or 'AutoPatches' in x for x in deps),'Compatibility library found')
 return {'name':path.name,'minOS':'15.0','arch':'arm64e','dependencies':deps}
def main():
 p=argparse.ArgumentParser();p.add_argument('--stage',type=pathlib.Path);a=p.parse_args();check_locale()
 c=dict(x.split(': ',1) for x in (ROOT/'control').read_text().splitlines() if ': 'in x)
 require(c['Package']=='com.doimty.quiethosts' and c['Version']=='0.1.0-1+native6','Package identity mismatch')
 for folder in ('App','Module'):
  info=plist(ROOT/folder/'Resources/Info.plist')
  require(info['MinimumOSVersion']=='15.0','Wrong deployment target')
  require(info['CFBundleVersion']=='6','Wrong bundle build number')
  require(info['CFBundleLocalizations']==['en','zh-Hans'],'Locales missing')
 moduleInfo=plist(ROOT/'Module/Resources/Info.plist')
 require(moduleInfo['CFBundlePackageType']=='BNDL','CC module is not a bundle')
 require(moduleInfo['CFBundleSupportedPlatforms']==['iPhoneOS'],'CC module platform metadata missing')
 require(moduleInfo['CFBundleExecutable']=='QuietHostsModule' and moduleInfo['NSPrincipalClass']=='QuietHostsModule','CC module principal executable mismatch')
 for name in ('postinst','prerm','postrm'):
  text=(ROOT/'layout/DEBIAN'/name).read_text();require('rm 'not in text and 'cp 'not in text,'Unsafe maintainer file operation')
 require('restore-for-uninstall' in (ROOT/'layout/DEBIAN/prerm').read_text(),'No checked removal')
 if a.stage:
  from localization_core import parse_strings
  s=a.stage;app=s/'Applications/QuietHosts.app';module=s/'Library/ControlCenter/Bundles/QuietHostsModule.bundle';helper=s/'usr/libexec/quiethosts-helper'
  stagedModuleInfo=plist(module/'Info.plist')
  require(stagedModuleInfo==moduleInfo,'Staged CC module metadata mismatch')
  require(stagedModuleInfo.get('CFBundleSupportedPlatforms')==['iPhoneOS'],'Packaged CC module lacks iPhoneOS platform metadata')
  for p in (app/'QuietHosts',module/'QuietHostsModule',helper):print(macho(p))
  require(stat.S_IMODE(helper.stat().st_mode)==0o4755,'Helper not setuid')
  for bundle in (app,module):
   for locale in ('en','zh-Hans'):
    p=bundle/(locale+'.lproj')/'Localizable.strings';raw=p.read_bytes();value=plistlib.loads(raw) if raw.startswith((b'bplist',b'<?xml')) else parse_strings(raw.decode())
    require(value==parse_strings((ROOT/'App/Resources'/(locale+'.lproj')/'Localizable.strings').read_text()),'Locale payload mismatch')
  for file in s.rglob('*'):
   rel=file.relative_to(s).as_posix()
   if file.is_file():require(rel.startswith(('Applications/QuietHosts.app/','Library/ControlCenter/Bundles/QuietHostsModule.bundle/','usr/libexec/quiethosts-helper','usr/share/doc/com.doimty.quiethosts/','DEBIAN/')),'Unexpected payload '+rel)
  require(not list(s.rglob('*.roothidepatch')),'Conversion payload present')
 print('QuietHosts source/staging validation passed')
if __name__=='__main__':main()
