#import "QHStatusPresentation.h"
#import "QHLocalization.h"

static BOOL TrueBoolean(id value) {
    return [value isKindOfClass:NSNumber.class] &&
           CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() && [value boolValue];
}
BOOL QHStatusRequiresAdoption(id status) {
    return [status isKindOfClass:NSDictionary.class] && TrueBoolean(status[@"ok"]) &&
           [status[@"state"] isKindOfClass:NSString.class] && [status[@"state"] isEqual:@"unmanaged"] &&
           TrueBoolean(status[@"requiresAdoption"]);
}
NSString *QHStatusErrorCode(id status) {
    if (![status isKindOfClass:NSDictionary.class]) {
        return @"unknown-error";
    }
    id code = status[@"errorCode"];
    if (![code isKindOfClass:NSString.class] || ![code length] || [code length] > 80) {
        return @"unknown-error";
    }
    NSCharacterSet *allowed =
        [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789-"];
    return [code rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound ? code
                                                                                     : @"unknown-error";
}
NSString *QHStatusExplanation(id value) {
    if (!value) {
        return QHL(@"Checking file state");
    }
    NSDictionary *status = [value isKindOfClass:NSDictionary.class] ? value : @{};
    if (QHStatusRequiresAdoption(status)) {
        return QHL(@"A basic Hosts file is present but has not been adopted. First Apply requires explicit "
                   @"permission to back up this exact file. Disabling will restore its original contents, "
                   @"not replace it with a generic default.");
    }
    id ok = status[@"ok"];
    if ([ok isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)ok) == CFBooleanGetTypeID() &&
        [ok boolValue]) {
        NSString *state = status[@"state"];
        if ([state isEqual:@"active"]) {
            return QHL(@"This is verified file state, not a DNS or traffic protection test. Apps may retain "
                       @"cached DNS results.");
        }
        if ([state isEqual:@"inactive"]) {
            return QHL(@"QuietHosts rules are paused. The helper restored its verified original Hosts state; "
                       @"this does not test DNS behavior.");
        }
        if ([state isEqual:@"unmanaged"]) {
            return QHL(@"No QuietHosts rules have been applied. The original system Hosts file has not been "
                       @"written.");
        }
        return QHL(@"The helper returned a file status, but it does not verify DNS or traffic protection.");
    }
    NSString *code = QHStatusErrorCode(status);
    NSString *detail;
    if ([code isEqual:@"adoption-required"]) {
        detail = QHL(@"This basic Hosts file needs a separate backup-and-adopt confirmation. No takeover was "
                     @"authorized by this request. Check file state and review the first-apply preview.");
    } else if ([code isEqual:@"paired-root-conflict"]) {
        detail = QHL(@"The paired RootHide data directory or its linking relationship could not be verified. "
                     @"Keep both roots and links unchanged; report this diagnostic code instead of changing "
                     @"their permissions.");
    } else if ([code isEqual:@"unmanaged-target"]) {
        detail = QHL(@"A regular Hosts file already exists at the managed entry. QuietHosts has not verified "
                     @"its origin and will not take it over automatically. Keep the file for inspection; do "
                     @"not delete it to force activation.");
    } else if ([code isEqual:@"secondary-conflict"]) {
        detail = QHL(@"A secondary hosts.lmb entry exists and may take precedence after switching. Keep it "
                     @"unchanged until its owner and purpose are verified.");
    } else if ([code isEqual:@"mirror-conflict"]) {
        detail = QHL(
            @"The Hosts mirror link could not be verified as the original system file. This may be an "
            @"unsupported path layout, not a conflicting ad list. Keep the link unchanged for diagnosis.");
    } else if ([@[
                   @"unsafe-directory", @"unsafe-root-directory", @"unsafe-var-layout", @"unsafe-var-link",
                   @"unsafe-system-directory", @"root-alias"
               ] containsObject:code]) {
        detail = QHL(@"The directory layout or ownership did not meet the helper's safety checks. This can "
                     @"be a compatibility issue with the real RootHide layout. Do not change ownership or "
                     @"remove directories to bypass it.");
    } else if ([@[
                   @"metadata-invalid", @"journal-invalid", @"journal-lineage", @"backup-corrupt",
                   @"snapshot-corrupt", @"orphan-backup", @"orphan-preparation", @"lock-missing"
               ] containsObject:code]) {
        detail = QHL(@"The helper found incomplete or inconsistent transaction state. Keep its state "
                     @"directory and backups; clearing them may lose recovery information.");
    } else if ([code isEqual:@"revision-conflict"] || [code isEqual:@"busy"]) {
        detail = QHL(@"The file state changed or another operation is running. Check file state again before "
                     @"making a new confirmation.");
    } else if ([code isEqual:@"baseline-conflict"]) {
        detail = QHL(@"A generated domain overlaps an existing original Hosts mapping. Exclude that exact "
                     @"domain or review the original mapping before applying.");
    } else if ([@[
                   @"target-conflict", @"file-raced", @"directory-raced", @"system-changed",
                   @"system-directory-changed", @"recovery-conflict", @"staging-conflict", @"lock-raced"
               ] containsObject:code]) {
        detail = QHL(@"Files or directories changed since the verified snapshot. Keep all current files and "
                     @"backups for comparison; no forced overwrite is available.");
    } else if ([code isEqual:@"permission-denied"] || [code hasPrefix:@"helper-"]) {
        detail =
            QHL(@"The helper could not verify file state. Check the native RootHide package and "
                @"dependencies, then check again. Do not remove existing Hosts files to force activation.");
    } else {
        detail = QHL(@"The operation could not be verified. Keep the current files and report the diagnostic "
                     @"code; it does not identify a specific conflicting application by itself.");
    }
    return [NSString stringWithFormat:QHL(@"%@\n\nDiagnostic code: %@"), detail, code];
}
