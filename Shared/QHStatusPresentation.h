#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Sanitized, display-only diagnostic functions. Never query a helper or a file.
FOUNDATION_EXPORT BOOL QHStatusRequiresAdoption(id _Nullable status);
FOUNDATION_EXPORT NSString *QHStatusErrorCode(id _Nullable status);
FOUNDATION_EXPORT NSString *QHStatusExplanation(id _Nullable status);
NS_ASSUME_NONNULL_END
