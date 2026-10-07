import hashlib,json,pathlib,subprocess,tarfile,urllib.request
ROOT=pathlib.Path(__file__).resolve().parents[1]
THEOS='88506b2c22e9e07dd4ed055f23c9e398a117a2c7'
SDK_URL='https://github.com/theos/sdks/releases/download/master-146e41f/iPhoneOS16.5.sdk.tar.xz'
SDK_SHA='5e0fd3f01266cce4ce012d4a99b38eb56578fca40d09edc81cd83dee958202fb'
def run(*args):subprocess.run(args,check=True)
if __name__=='__main__':
 import argparse
 p=argparse.ArgumentParser();p.add_argument('--theos',type=pathlib.Path,required=True);p.add_argument('--work',type=pathlib.Path,required=True);a=p.parse_args();a.work.mkdir(parents=True,exist_ok=True)
 run('git','clone','https://github.com/roothide/theos.git',str(a.theos))
 run('git','-C',str(a.theos),'fetch','--depth','1','origin',THEOS)
 run('git','-C',str(a.theos),'checkout',THEOS)
 run('git','-C',str(a.theos),'submodule','update','--init','--recursive')
 archive=a.work/'sdk.tar.xz'
 run('curl','--fail','--location','--retry','3',SDK_URL,'-o',str(archive))
 assert hashlib.sha256(archive.read_bytes()).hexdigest()==SDK_SHA,'SDK hash mismatch'
 run('tar','-xJf',str(archive),'-C',str(a.theos/'sdks'))
 assert (a.theos/'sdks/iPhoneOS16.5.sdk').is_dir()
 (a.work/'inputs.json').write_text(json.dumps({'theos':THEOS,'sdk':SDK_URL,'sdk_sha256':SDK_SHA,'dependencies_rebuilt':False},indent=2)+'\n')
