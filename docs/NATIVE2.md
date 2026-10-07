# Native2: device layout repair and explicit baseline adoption

Supersedes preliminary routing assumptions in DEVICE_LAYOUT_FIX.md and the first-version ordinary-file refusal in PLAN.md. First release source60f2a5a refused actual rootUID501 and splitvar links; the timeout candidate also incorrectly required pairedvarUID0. Native2 supports primaryroot0755uid501, private/etc/pairedroot/libroot0, pairedvar0755uid501 without changing those directories. Only mainroot and explicitly derived pairvar have the501 exception; protectedchildren stayroot. No old dependency is rebuilt.

Pairing uses currentjbrand in the nativehelper and `/var/mobile/Containers/Shared/AppGroup/.jbroot-<brand>/var`. Primary rootname mustmatchbrand, private/varlinkandsecondary `.jbroot` backlink mustmatchnative orfixedcanonicalalias. Terminal/rootfsdisplayisnot acceptedas arbitrarynativeprefix. AllunderlyingFDsandentriesareanchored; parentsreopenedwithnofollow; routingdirectorieswhichhelperneverdirectlychangesalsopinmtime/ctime,size,nlink.

RegulardefaultHosts eligibility: UTF8<=1MiB, rootregular0644singlelink, exactlythree conventional mappings(127.0.0.1localhost,255.255.255.255broadcasthost,::1localhost) withcomments/whitespace. No othermapping. Statusisread-onlyexceptexistingjournalrecovery; eligiblecase stateunmanaged requiresAdoptiontrue. Applyconfirmation capturesrevisionandadoptExistingHosts=true onlyafterexplicituserapproval. No flag/string/integer flag/foreign target/changedrevision → refuse. Backupisexactexistingregularbytes, notrawsystemcopy. Newstateversion2 supportsregularoriginal, version1mirror/missingremainreadable. Disable restoresoriginalbyte/hash/modeuidgid; inodechangesduetoatomicreplacement. Originalbaselineandrawsystemare independentlyvalidated, rawsystemneverwritten. Oldnative1cannotinterpretv2state: downgrade isnot a validatedrecoverymethod.

## Review fixes
Parent fixedregularinactive load incorrectly invokingmirror-onlyvalidation afterrestore; existing corruption test nowusesunsupportedversion999 because2isvalid. Added preciseoriginalGIDtest againstpre-adoptionmetadata. DirectorypolicyNULnegativepassesactuallengthratherthanstrlen-truncatedvalue. Retainednewtestsandalloldsuites.

## Remaining concurrency boundary
FixedFDs preventredirectingwritesintoanattacker-createdreplacement/symlink, but aren'tanatomicnamespacelock. Testseamafter-check:commit-target deliberatelyrunsafterLASTcheck: movingetcawayandbackcanbe followedbyrenameintoalreadyvalidatedFD; nexttimestampguardrejectswithchangedtrue andjournal/backupretained. Thisisnotzero-writeorzeroTOCTOU. Raw/foreignfilesarepreserved; rootadversaryisnotcovered. Repeatedroutingchangesmaycauseavailabilityfailuresinstead offorcedoverwrites.

## Verification gates
- C directorypolicyUID/type/mode/text/nulltests withbaselinefailnegative.
- macOSrealFoundationoldtransactions/newsplitroots, explicitadopt/restore/enable, wronglinks/brands/backlink, foreignfiles, CAS/consentfailures, journalcrashes.
- AdditionaldisposableCIrootrun ONLY `--mixed-uid` fixture: primaryroot501 andpairedvar501, protectedchildren0, immutableoriginalbackup; eachprotectedchildchangedto501mustrefuse. Thisisnotrunningtheproductionhelperorinstallingadeb.
- Originalparser/draftstore/download/transport/localechecks retained. Signedentitlements/numericarchiveUID/GID/4755helper andrealdebchecksretained.
- Devicecurrentlynative1: actualnewUI, nativehelperrouteacceptance, write/reload/disable andenergyareNOTprovenbycloudtests. No installation, chmod/chown or service restart onuserdeviceinthischange.
