#include "../Helper/QHRootlessRouting.h"
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned checks, failures;
static void check(int yes, const char *name) { checks++; if (!yes) { failures++; fprintf(stderr,"FAIL: %s\n",name); } }
static void setup(int yes) { if(!yes) { perror("fixture"); exit(2); } }
static void want(const char *got, const char *expected) {
    check(expected ? got && strcmp(got,expected)==0 : got==NULL, expected ? expected : "routing valid");
}
int main(int argc,char **argv) {
    if(argc!=2) return 2;
    int base=open(argv[1],O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC); setup(base>=0);
    setup(mkdirat(base,"sandbox",0755)==0);
    int box=openat(base,"sandbox",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);setup(box>=0);
    setup(mkdirat(box,"managed",0755)==0 && mkdirat(box,"raw",0755)==0);
    int root=openat(box,"managed",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);setup(root>=0);
    setup(mkdirat(root,"etc",0755)==0 && mkdirat(root,"var",0755)==0);
    int var=openat(root,"var",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);setup(var>=0);
    setup(mkdirat(var,"lib",0755)==0);
    setup(symlinkat("/sandbox/managed",box,"jb")==0);
    QHRootlessRouting value={.baseFD=-1};
    want(QHRootlessRoutingOpen(base,"sandbox/managed","sandbox/raw","sandbox","jb",geteuid(),&value),NULL);
    check(value.baseFD>=0 && (fcntl(value.baseFD,F_GETFD)&FD_CLOEXEC),"anchor owns a close-on-exec base fd");
    want(QHRootlessRoutingVerify(&value),NULL);
    setup(mkdirat(var,"lib/quiethosts",0700)==0);
    want(QHRootlessRoutingVerify(&value),NULL); /* state creation does not invalidate namespace */
    setup(renameat(root,"etc",root,"etc.saved")==0 && mkdirat(root,"etc",0755)==0);
    want(QHRootlessRoutingVerify(&value),"rootless-namespace-changed");
    setup(unlinkat(root,"etc",AT_REMOVEDIR)==0 && renameat(root,"etc.saved",root,"etc")==0);
    want(QHRootlessRoutingVerify(&value),NULL);
    setup(fchmod(box,0775)==0);
    want(QHRootlessRoutingVerify(&value),"rootless-unsafe-namespace");
    setup(fchmod(box,0755)==0);
    setup(renameat(box,"jb",box,"jb.saved")==0 && symlinkat("/sandbox/raw",box,"jb")==0);
    want(QHRootlessRoutingVerify(&value),"rootless-dependency-root-conflict");
    setup(unlinkat(box,"jb",0)==0 && symlinkat("/sandbox/managed",box,"jb")==0);
    want(QHRootlessRoutingVerify(&value),"rootless-dependency-root-conflict"); /* equal text, different identity */
    setup(unlinkat(box,"jb",0)==0 && renameat(box,"jb.saved",box,"jb")==0);
    /* Renaming back may change link ctime; the original anchor conservatively refuses. */
    QHRootlessRoutingClose(&value);
    want(QHRootlessRoutingOpen(base,"sandbox/managed","sandbox/raw","sandbox","jb",geteuid(),&value),NULL);
    want(QHRootlessRoutingVerify(&value),NULL);
    QHRootlessRoutingClose(&value);check(value.baseFD==-1,"closed anchor is invalidated");
    want(QHRootlessRoutingVerify(&value),"rootless-invalid-preflight");
    /* A direct-directory /var/jb style alias must be the exact physical root. */
    want(QHRootlessRoutingOpen(base,"sandbox/managed","sandbox/raw","sandbox","managed",geteuid(),&value),NULL);
    want(QHRootlessRoutingVerify(&value),NULL);QHRootlessRoutingClose(&value);
    want(QHRootlessRoutingOpen(base,"sandbox/managed","sandbox/raw","sandbox","raw",geteuid(),&value),"rootless-dependency-root-conflict");
    setup(unlinkat(box,"jb",0)==0 && symlinkat("managed",box,"jb")==0);
    want(QHRootlessRoutingOpen(base,"sandbox/managed","sandbox/raw","sandbox","jb",geteuid(),&value),"rootless-dependency-root-conflict");
    setup(unlinkat(box,"jb",0)==0 && symlinkat("/sandbox/managed/",box,"jb")==0);
    want(QHRootlessRoutingOpen(base,"sandbox/managed","sandbox/raw","sandbox","jb",geteuid(),&value),NULL);QHRootlessRoutingClose(&value);
    setup(symlinkat("sandbox",base,"shortcut")==0);
    want(QHRootlessRoutingOpen(base,"shortcut/managed","sandbox/raw","sandbox","jb",geteuid(),&value),"rootless-unsafe-namespace");
    want(QHRootlessRoutingOpen(base,"sandbox/../sandbox/managed","sandbox/raw","sandbox","jb",geteuid(),&value),"rootless-invalid-preflight");
    want(QHRootlessRoutingOpen(base,"sandbox//managed","sandbox/raw","sandbox","jb",geteuid(),&value),"rootless-invalid-preflight");
    want(QHRootlessRoutingOpen(base,"/sandbox/managed","sandbox/raw","sandbox","jb",geteuid(),&value),"rootless-invalid-preflight");
    want(QHRootlessRoutingOpen(base,"sandbox/managed","sandbox/managed/etc","sandbox","jb",geteuid(),&value),"root-alias");
    int freeFD=dup(base);setup(freeFD>=0);close(freeFD);
    for(unsigned i=0;i<128;i++) {
        want(QHRootlessRoutingOpen(base,"sandbox/managed","sandbox/raw","sandbox","jb",geteuid(),&value),NULL);
        want(QHRootlessRoutingVerify(&value),NULL);QHRootlessRoutingClose(&value);
    }
    int again=dup(base);setup(again>=0);check(again==freeFD,"repeated route guards leak no descriptors");close(again);
    check(fcntl(base,F_GETFD)>=0,"caller base fd preserved");
    close(var);close(root);close(box);close(base);
    printf("RootlessRouting: %u checks, %u failures\n",checks,failures);return failures?1:0;
}
