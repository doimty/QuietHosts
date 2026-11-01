import argparse, pathlib,plistlib,stat,struct,sys,re
ROOT=pathlib.Path(__file__).resolve().parents[1]
from check_localization import check as check_locale

def require(value,message):
 if not value:raise ValueError(message)
def plist(path):return plistlib.loads(path.read_bytes())
def macho(path,scheme='roothide'):
    """Check thin executable/header/command layout, not full codesign validity."""
    require(scheme in ('roothide','rootless'),'Unknown platform scheme')
    raw=path.read_bytes()
    require(len(raw)>=32 and raw[:4]==b'\xcf\xfa\xed\xfe','Expected thin Mach-O')
    _,cpu,subtype,kind,count,size,_,_=struct.unpack_from('<8I',raw)
    expectedSubtype=2 if scheme=='roothide' else 0
    require(cpu==0x100000c and (subtype&0xffffff)==expectedSubtype,'Wrong CPU architecture for '+scheme)
    if scheme=='roothide':
        require(subtype&0x80000000,'RootHide arm64e PAC capability missing')
    require(kind==2,'Expected Mach-O executable')
    end=32+size
    require(end<=len(raw),'Bad command area')
    require(count<=size//8,'Bad command count')
    pos=32;minimums=[];signed=False;deps=[];rpaths=[]

    def command_string(minimum,label,n):
        offset=struct.unpack_from('<I',raw,pos+8)[0]
        require(minimum<=offset<n,'Bad '+label+' offset')
        start=pos+offset;stop=raw.find(b'\0',start,pos+n)
        require(stop>start,'Bad '+label+' string')
        try:return raw[start:stop].decode('utf-8')
        except UnicodeDecodeError as error:raise ValueError('Bad '+label+' string encoding') from error

    for _ in range(count):
        require(pos+8<=end,'Bad command area')
        cmd,n=struct.unpack_from('<II',raw,pos)
        require(n>=8 and n%8==0 and pos+n<=end,'Bad command')
        if cmd==0x32:
            require(n>=24,'Bad build version command')
            platform,v,sdk,tools=struct.unpack_from('<4I',raw,pos+8)
            require(n==24+tools*8,'Bad build version tools')
            require(platform==2,'Not iOS')
            minimums.append(v)
        if cmd==0x25:
            require(n==16,'Bad minimum version command')
            minimums.append(struct.unpack_from('<I',raw,pos+8)[0])
        if cmd==0x1d:
            require(n==16,'Bad signature command')
            offset,length=struct.unpack_from('<II',raw,pos+8)
            require(not signed and length>0 and offset>=end and offset+length<=len(raw),'Bad signature')
            # Only LC_CODE_SIGNATURE presence and its file-backed data range.
            # CodeDirectory hashes, entitlements and trust are not verified here.
            signed=True
        if cmd in (0xc,0x80000018,0x8000001f,0x20,0x80000023):
            require(n>=24,'Bad dependency command')
            deps.append(command_string(24,'dependency',n))
        if cmd==0x8000001c:
            require(n>=12,'Bad rpath command')
            rpaths.append(command_string(12,'rpath',n))
        pos+=n
    require(pos==end,'Bad command area')
    require(minimums and all(v==15<<16 for v in minimums) and signed,'Missing minOS/signature')
    forbidden=('AutoPatches',) + (('/var/jb',) if scheme=='roothide' else ('libroothide','.roothidepatch'))
    require(not any(x in name for name in deps+rpaths for x in forbidden),'Wrong platform or compatibility library found')
    if scheme=='rootless':require('/var/jb/usr/lib' in rpaths and '@loader_path/.jbroot/usr/lib' in rpaths,'Rootless rpath missing')
    return {'name':path.name,'minOS':'15.0','arch':'arm64e' if scheme=='roothide' else 'arm64',
            'cpusubtype':hex(subtype),'caps':hex(subtype>>24),'dependencies':deps,'rpaths':rpaths,
            'signature':'LC_CODE_SIGNATURE data range present; NOT full codesign verification'}
def main():
 p=argparse.ArgumentParser();p.add_argument('--stage',type=pathlib.Path);p.add_argument('--scheme',choices=('roothide','rootless'),default='roothide');p.add_argument('--release',action='store_true',help='Reject nonnumeric package versions for formal releases');a=p.parse_args();check_locale()
 c=dict(x.split(': ',1) for x in (ROOT/'control').read_text(encoding='utf-8').splitlines() if ': 'in x)
 require(c['Architecture']=='iphoneos-arm64e','Source control must preserve RootHide architecture')
 if a.scheme=='rootless':c['Architecture']='iphoneos-arm64'
 if a.release:require(re.fullmatch(r'[0-9]+(?:\.[0-9]+)*(?:-[0-9]+)?',c['Version']) is not None,'Formal release version must be numeric (no native/beta suffix)')
 require(c['Package']=='com.doimty.quiethosts' and c['Version']=='0.1.0-1+native34','Package identity mismatch')
 require(c['Section']=='Applications','Package section must be Applications')
 info=plist(ROOT/'App/Resources/Info.plist')
 require(info['MinimumOSVersion']=='15.0','Wrong deployment target')
 require(info['CFBundleVersion']=='34','Wrong bundle build number')
 require(info['CFBundleShortVersionString']=='0.1.0','Wrong App version')
 workflow=(ROOT/'.github/workflows/native.yml').read_text(encoding='utf-8')
 require('deb=packages/'+c['Package']+'_'+c['Version']+'_${arch}.deb' in workflow,'CI package filename mismatch')
 require('arch=iphoneos-arm64e' in workflow and 'then arch=iphoneos-arm64; prefix=var/jb/;' in workflow,'CI scheme/architecture mapping mismatch')
 require('scheme: [roothide, rootless]' in workflow and 'name: quiethosts-native-${{ matrix.scheme }}-${{ github.run_id }}-${{ github.run_attempt }}' in workflow,'CI dual-environment identity mismatch')
 require(info['CFBundleLocalizations']==['en','zh-Hans'],'Locales missing')
 from test_native10_ui import check_icon
 for name,size in [('Icon1024.png',1024),('Icon60@3x.png',180),('Icon60@2x.png',120)]:
  check_icon(ROOT/'App/Resources'/name,size)
 layout=ROOT/('layout-rootless' if a.scheme=='rootless' else 'layout')
 for name in ('postinst','prerm','postrm'):
  text=(layout/'DEBIAN'/name).read_text(encoding='utf-8');require('rm 'not in text and 'cp 'not in text,'Unsafe maintainer file operation')
 require('restore-for-uninstall' in (layout/'DEBIAN/prerm').read_text(encoding='utf-8'),'No checked removal')
 if a.stage:
  from localization_core import parse_strings
  s=a.stage;payload=s/'var/jb' if a.scheme=='rootless' else s
  app=payload/'Applications/QuietHosts.app';helper=payload/'usr/libexec/quiethosts-helper'
  staged=plist(app/'Info.plist')
  for key in ('CFBundleVersion','CFBundleShortVersionString','CFBundleIdentifier','MinimumOSVersion'):
   require(staged[key]==info[key],'Staged App metadata mismatch: '+key)
  packaged=dict(x.split(': ',1) for x in (s/'DEBIAN/control').read_text(encoding='utf-8').splitlines() if ': ' in x)
  for key in ('Package','Version','Architecture','Section','Depends','Conflicts'):
   require(packaged[key]==c[key],'Staged package metadata mismatch: '+key)
  for name,size in [('Icon1024.png',1024),('Icon60@3x.png',180),('Icon60@2x.png',120)]:
   check_icon(app/name,size)
   require((app/name).read_bytes()==(ROOT/'App/Resources'/name).read_bytes(),'Staged icon mismatch: '+name)
  for p in (app/'QuietHosts',helper):print(macho(p,a.scheme))
  require(stat.S_IMODE(helper.stat().st_mode)==0o4755,'Helper not setuid')
  for locale in ('en','zh-Hans'):
   p=app/(locale+'.lproj')/'Localizable.strings';raw=p.read_bytes();value=plistlib.loads(raw) if raw.startswith((b'bplist',b'<?xml')) else parse_strings(raw.decode())
   require(value==parse_strings((ROOT/'App/Resources'/(locale+'.lproj')/'Localizable.strings').read_text(encoding='utf-8')),'Locale payload mismatch')
  prefix='var/jb/' if a.scheme=='rootless' else ''
  allowed=tuple(prefix+x for x in ('Applications/QuietHosts.app/','usr/libexec/quiethosts-helper','usr/share/doc/com.doimty.quiethosts/'))+('DEBIAN/',)
  for file in s.rglob('*'):
   rel=file.relative_to(s).as_posix()
   if file.is_file():require(rel.startswith(allowed),'Unexpected payload '+rel)
  for name in ('postinst','prerm','postrm'):
   require((s/'DEBIAN'/name).read_bytes()==(layout/'DEBIAN'/name).read_bytes(),'Maintainer script mismatch: '+name)
  require(not list(s.rglob('*.roothidepatch')),'Conversion payload present')
 print('QuietHosts staging validation passed (NOT full codesign/device proof)' if a.stage else 'QuietHosts source validation passed (staging/setuid NOT RUN)')
if __name__=='__main__':main()
