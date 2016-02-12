#import "CodePush.h"
#import "SSZipArchive.h"

@implementation CodePushPackage

NSString * const CodePushErrorDomain = @"CodePushError";
const int CodePushErrorCode = -1;
NSString * const DiffManifestFileName = @"hotcodepush.json";
NSString * const DownloadFileName = @"download.zip";
NSString * const RelativeBundlePathKey = @"bundlePath";
NSString * const StatusFile = @"codepush.json";
NSString * const UpdateBundleFileName = @"app.jsbundle";
NSString * const UnzippedFolderName = @"unzipped";

+ (NSString *)getCodePushPath
{
    NSString* codePushPath = [[CodePush getApplicationSupportDirectory] stringByAppendingPathComponent:@"CodePush"];
    if ([CodePush isUsingTestConfiguration]) {
        codePushPath = [codePushPath stringByAppendingPathComponent:@"TestPackages"];
    }
    
    return codePushPath;
}

+ (NSString *)getDownloadFilePath
{
    return [[self getCodePushPath] stringByAppendingPathComponent:DownloadFileName];
}

+ (NSString *)getUnzippedFolderPath
{
    return [[self getCodePushPath] stringByAppendingPathComponent:UnzippedFolderName];
}

+ (NSString *)getStatusFilePath
{
    return [[self getCodePushPath] stringByAppendingPathComponent:StatusFile];
}

+ (NSMutableDictionary *)getCurrentPackageInfo
{
    NSString *statusFilePath = [self getStatusFilePath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:statusFilePath]) {
        return [NSMutableDictionary dictionary];
    }
    
    NSError *error;
    NSString *content = [NSString stringWithContentsOfFile:statusFilePath
                                                  encoding:NSUTF8StringEncoding
                                                     error:&error];
    if (error) {
        // File is corrupted, delete it.
        NSLog(@"Error reading contents of status file %@: %@", statusFilePath, error);
        NSError *deleteError;
        [[NSFileManager defaultManager] removeItemAtPath:statusFilePath
                                                   error:&deleteError];
        if (deleteError) {
            NSLog(@"Error deleting status file %@: %@", statusFilePath, deleteError);
        }
        
        return [NSMutableDictionary dictionary];
    }
    
    NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary* json = [NSJSONSerialization JSONObjectWithData:data
                                                         options:kNilOptions
                                                           error:&error];
    if (error) {
        // File is corrupted, delete it.
        NSLog(@"Error parsing contents of status file %@: %@", statusFilePath, error);
        NSError *deleteError;
        [[NSFileManager defaultManager] removeItemAtPath:statusFilePath
                                                   error:&deleteError];
        if (deleteError) {
            NSLog(@"Error deleting status file %@: %@", statusFilePath, deleteError);
        }
        
        return [NSMutableDictionary dictionary];
    }
    
    return [json mutableCopy];
}

+ (void)updateCurrentPackageInfo:(NSDictionary *)packageInfo
                           error:(NSError **)error
{
    
    NSData *packageInfoData = [NSJSONSerialization dataWithJSONObject:packageInfo
                                                              options:0
                                                                error:error];
    
    NSString *packageInfoString = [[NSString alloc] initWithData:packageInfoData
                                                        encoding:NSUTF8StringEncoding];
    [packageInfoString writeToFile:[self getStatusFilePath]
                        atomically:YES
                          encoding:NSUTF8StringEncoding
                             error:error];
}

+ (NSString *)getCurrentPackageFolderPath
{
    NSDictionary *info = [self getCurrentPackageInfo];
    if (info) {
        NSString *packageHash = info[@"currentPackage"];
        
        if (!packageHash) {
            return nil;
        }
        
        return [self getPackageFolderPath:packageHash];
    }
    
    return nil;
}

+ (NSString *)getCurrentPackageBundlePath
{
    NSString *packageFolder = [self getCurrentPackageFolderPath];
    NSDictionary *currentPackage = [self getCurrentPackage];
    
    if (packageFolder && currentPackage) {
        NSString *relativeBundlePath = [currentPackage objectForKey:RelativeBundlePathKey];
        if (relativeBundlePath) {
            return [packageFolder stringByAppendingPathComponent:relativeBundlePath];
        } else {
            return [packageFolder stringByAppendingPathComponent:UpdateBundleFileName];
        }
    }
    
    return nil;
}

+ (NSString *)getCurrentPackageHash
{
    NSDictionary *info = [self getCurrentPackageInfo];
    if (info) {
        return info[@"currentPackage"];
    }
    
    return nil;
}

+ (NSString *)getPreviousPackageHash:(NSError **)error
{
    NSDictionary *info = [self getCurrentPackageInfo];
    if (info) {
        return info[@"previousPackage"];
    }
    
    return nil;
}

+ (NSDictionary *)getCurrentPackage
{
    NSString *currentPackageHash = [CodePushPackage getCurrentPackageHash];
    if (currentPackageHash) {
        return [CodePushPackage getPackage:currentPackageHash];
    }
    
    return nil;
}

+ (NSDictionary *)getPackage:(NSString *)packageHash
{
    NSString *folderPath = [self getPackageFolderPath:packageHash];
    if (![[NSFileManager defaultManager] fileExistsAtPath:folderPath]) {
        return nil;
    }
    
    NSString *packageFilePath = [folderPath stringByAppendingPathComponent:@"app.json"];
    
    NSError *error;
    NSString *content = [NSString stringWithContentsOfFile:packageFilePath
                                                  encoding:NSUTF8StringEncoding
                                                     error:&error];
    if (error) {
        NSLog(@"Error reading contents of update metadata file %@: %@", packageFilePath, error);
        return nil;
    }
    
    NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary* jsonDict = [NSJSONSerialization JSONObjectWithData:data
                                                             options:kNilOptions
                                                               error:&error];
    if (error) {
        NSLog(@"Error parsing contents of update metadata file %@: %@", packageFilePath, error);
        return nil;
    }
    
    return jsonDict;
}

+ (NSString *)getPackageFolderPath:(NSString *)packageHash
{
    return [[self getCodePushPath] stringByAppendingPathComponent:packageHash];
}

+ (BOOL)isCodePushError:(NSError *)err
{
    return err != nil && [CodePushErrorDomain isEqualToString:err.domain];
}

+ (void)downloadPackage:(NSDictionary *)updatePackage
       progressCallback:(void (^)(long long, long long))progressCallback
           doneCallback:(void (^)())doneCallback
           failCallback:(void (^)(NSError *err))failCallback
{
    NSString *newPackageFolderPath = [self getPackageFolderPath:updatePackage[@"packageHash"]];
    NSError *error = nil;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:newPackageFolderPath]) {
        // This removes any downloaded data that could have been left
        // uncleared due to a crash or error during the download process.
        [[NSFileManager defaultManager] removeItemAtPath:newPackageFolderPath
                                                   error:&error];
        if (error) {
            failCallback(error);
            return;
        }
    }
    
    [[NSFileManager defaultManager] createDirectoryAtPath:newPackageFolderPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&error];
    if (error) {
        failCallback(error);
        return;
    }
    
    NSString *downloadFilePath = [self getDownloadFilePath];
    NSString *bundleFilePath = [newPackageFolderPath stringByAppendingPathComponent:UpdateBundleFileName];
    
    CodePushDownloadHandler *downloadHandler = [[CodePushDownloadHandler alloc]
        init:downloadFilePath
        progressCallback:progressCallback
        doneCallback:^(BOOL isZip) {
            NSError *error = nil;
            NSString * unzippedFolderPath = [CodePushPackage getUnzippedFolderPath];
            NSMutableDictionary * mutableUpdatePackage = [updatePackage mutableCopy];
            if (isZip) {
                if ([[NSFileManager defaultManager] fileExistsAtPath:unzippedFolderPath]) {
                    // This removes any unzipped download data that could have been left
                    // uncleared due to a crash or error during the download process.
                    [[NSFileManager defaultManager] removeItemAtPath:unzippedFolderPath
                                                               error:&error];
                    if (error) {
                        failCallback(error);
                        return;
                    }
                }
                
                NSError *nonFailingError = nil;
                [SSZipArchive unzipFileAtPath:downloadFilePath
                                toDestination:unzippedFolderPath];
                [[NSFileManager defaultManager] removeItemAtPath:downloadFilePath
                                                           error:&nonFailingError];
                if (nonFailingError) {
                    NSLog(@"Error deleting downloaded file: %@", nonFailingError);
                    nonFailingError = nil;
                }
                
                NSString *diffManifestFilePath = [unzippedFolderPath stringByAppendingPathComponent:DiffManifestFileName];
                
                if ([[NSFileManager defaultManager] fileExistsAtPath:diffManifestFilePath]) {
                    // Copy the current package to the new package.
                    NSString *currentPackageFolderPath = [self getCurrentPackageFolderPath];
                    if (!currentPackageFolderPath) {
                        error = [[NSError alloc] initWithDomain:CodePushErrorDomain
                                                           code:CodePushErrorCode
                                                       userInfo:@{
                                                                  NSLocalizedDescriptionKey:
                                                                      NSLocalizedString(@"No current package to apply diff update to.", nil)
                                                                  }];
                        failCallback(error);
                        return;
                    }
                    
                    [CodePushPackage copyEntriesInFolder:currentPackageFolderPath
                                              destFolder:newPackageFolderPath
                                                   error:&error];
                    if (error) {
                        failCallback(error);
                        return;
                    }
                    
                    // Delete files mentioned in the manifest.
                    NSString *manifestContent = [NSString stringWithContentsOfFile:diffManifestFilePath
                                                                          encoding:NSUTF8StringEncoding
                                                                             error:&error];
                    if (error) {
                        failCallback(error);
                        return;
                    }
                    
                    NSData *data = [manifestContent dataUsingEncoding:NSUTF8StringEncoding];
                    NSDictionary *manifestJSON = [NSJSONSerialization JSONObjectWithData:data
                                                                                 options:kNilOptions
                                                                                   error:&error];
                    NSArray *deletedFiles = manifestJSON[@"deletedFiles"];
                    for (NSString *deletedFileName in deletedFiles) {
                        [[NSFileManager defaultManager] removeItemAtPath:[newPackageFolderPath stringByAppendingPathComponent:deletedFileName]
                                                                   error:&nonFailingError];
                        
                        if (nonFailingError) {
                            NSLog(@"Error deleting file from current package: %@", nonFailingError);
                            nonFailingError = nil;
                        }
                    }
                }
                
                [CodePushPackage copyEntriesInFolder:unzippedFolderPath
                                          destFolder:newPackageFolderPath
                                               error:&error];
                if (error) {
                    failCallback(error);
                    return;
                }
                
                [[NSFileManager defaultManager] removeItemAtPath:unzippedFolderPath
                                                           error:&nonFailingError];
                if (nonFailingError) {
                    NSLog(@"Error deleting downloaded file: %@", nonFailingError);
                    nonFailingError = nil;
                }
                
                NSString *relativeBundlePath = [self findMainBundleInFolder:newPackageFolderPath
                                                                      error:&error];
                if (error) {
                    failCallback(error);
                    return;
                }
                
                if (relativeBundlePath) {
                    NSString *absoluteBundlePath = [newPackageFolderPath stringByAppendingPathComponent:relativeBundlePath];
                    NSDictionary *bundleFileAttributes = [[[NSFileManager defaultManager] attributesOfItemAtPath:absoluteBundlePath error:&error] mutableCopy];
                    if (error) {
                        failCallback(error);
                        return;
                    }
                    
                    [bundleFileAttributes setValue:[NSDate date] forKey:NSFileModificationDate];
                    [[NSFileManager defaultManager] setAttributes:bundleFileAttributes
                                                     ofItemAtPath:absoluteBundlePath
                                                            error:&error];
                    if (error) {
                        failCallback(error);
                        return;
                    }
                    
                    [mutableUpdatePackage setValue:relativeBundlePath forKey:RelativeBundlePathKey];
                } else {
                    error = [[NSError alloc] initWithDomain:CodePushErrorDomain
                                                       code:CodePushErrorCode
                                                   userInfo:@{
                                                              NSLocalizedDescriptionKey:
                                                                  NSLocalizedString(@"Update is invalid - no files with extension .jsbundle or .bundle were found in the update package.", nil)
                                                              }];
                    failCallback(error);
                    return;
                }
            } else {
                if ([[NSFileManager defaultManager] fileExistsAtPath:bundleFilePath]) {
                    [[NSFileManager defaultManager] removeItemAtPath:bundleFilePath error:&error];
                    if (error) {
                        failCallback(error);
                        return;
                    }
                }
                
                [[NSFileManager defaultManager] moveItemAtPath:downloadFilePath
                                                        toPath:bundleFilePath
                                                         error:&error];
                if (error) {
                    failCallback(error);
                    return;
                }
            }
            
            NSData *updateSerializedData = [NSJSONSerialization dataWithJSONObject:mutableUpdatePackage
                                                                           options:0
                                                                             error:&error];
            NSString *packageJsonString = [[NSString alloc] initWithData:updateSerializedData
                                                                encoding:NSUTF8StringEncoding];
            
            [packageJsonString writeToFile:[newPackageFolderPath stringByAppendingPathComponent:@"app.json"]
                                atomically:YES
                                  encoding:NSUTF8StringEncoding
                                     error:&error];
            if (error) {
                failCallback(error);
            } else {
                doneCallback();
            }
        }

        failCallback:failCallback];
    
    [downloadHandler download:updatePackage[@"downloadUrl"]];
}

+ (NSString *)findMainBundleInFolder:(NSString *)folderPath
                         error:(NSError **)error
{
    NSArray* folderFiles = [[NSFileManager defaultManager]
                                contentsOfDirectoryAtPath:folderPath
                                error:error];
    if (*error) {
        return nil;
    }
    
    for (NSString *fileName in folderFiles) {
        NSString *fullFilePath = [folderPath stringByAppendingPathComponent:fileName];
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:fullFilePath
                                                 isDirectory:&isDir] && isDir) {
            NSString *mainBundlePathInFolder = [self findMainBundleInFolder:fullFilePath error:error];
            if (*error) {
                return nil;
            }
            
            if (mainBundlePathInFolder) {
                return [fileName stringByAppendingPathComponent:mainBundlePathInFolder];
            }
        } else if ([[fileName pathExtension] isEqualToString:@"bundle"] ||
            [[fileName pathExtension] isEqualToString:@"jsbundle"] ||
            [[fileName pathExtension] isEqualToString:@"js"]) {
            return fileName;
        }
    }
    
    return nil;
}


+ (void)copyEntriesInFolder:(NSString *)sourceFolder
                 destFolder:(NSString *)destFolder
                      error:(NSError **)error

{
    NSArray* files = [[NSFileManager defaultManager]
                      contentsOfDirectoryAtPath:sourceFolder
                      error:error];
    if (*error) {
        return;
    }
    
    for (NSString *fileName in files) {
        NSString * fullFilePath = [sourceFolder stringByAppendingPathComponent:fileName];
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:fullFilePath
                                                isDirectory:&isDir] && isDir) {
            NSString *nestedDestFolder = [destFolder stringByAppendingPathComponent:fileName];
            [self copyEntriesInFolder:fullFilePath
                           destFolder:nestedDestFolder
                                error:error];
        } else {
            NSString *destFileName = [destFolder stringByAppendingPathComponent:fileName];
            if ([[NSFileManager defaultManager] fileExistsAtPath:destFileName]) {
                [[NSFileManager defaultManager] removeItemAtPath:destFileName error:error];
                if (*error) {
                    return;
                }
            }
            if (![[NSFileManager defaultManager] fileExistsAtPath:destFolder]) {
                [[NSFileManager defaultManager] createDirectoryAtPath:destFolder
                                          withIntermediateDirectories:YES
                                                           attributes:nil
                                                                error:error];
                if (*error) {
                    return;
                }
            }
            
            [[NSFileManager defaultManager] copyItemAtPath:fullFilePath toPath:destFileName error:error];
            if (*error) {
                return;
            }
        }
    }
}

+ (void)installPackage:(NSDictionary *)updatePackage
   removePendingUpdate:(BOOL)removePendingUpdate
                 error:(NSError **)error
{
    NSString *packageHash = updatePackage[@"packageHash"];
    NSMutableDictionary *info = [self getCurrentPackageInfo];
    if (removePendingUpdate) {
        NSString *currentPackageFolderPath = [self getCurrentPackageFolderPath];
        if (currentPackageFolderPath) {
            // Error in deleting pending package will not cause the entire operation to fail.
            NSError *deleteError;
            [[NSFileManager defaultManager] removeItemAtPath:currentPackageFolderPath
                                                       error:&deleteError];
            if (deleteError) {
                NSLog(@"Error deleting pending package: %@", deleteError);
            }
        }
    } else {
        NSString *previousPackageHash = [self getPreviousPackageHash:error];
        if (!*error && previousPackageHash && ![previousPackageHash isEqualToString:packageHash]) {
            NSString *previousPackageFolderPath = [self getPackageFolderPath:previousPackageHash];
            // Error in deleting old package will not cause the entire operation to fail.
            NSError *deleteError;
            [[NSFileManager defaultManager] removeItemAtPath:previousPackageFolderPath
                                                       error:&deleteError];
            if (deleteError) {
                NSLog(@"Error deleting old package: %@", deleteError);
            }
        }
        
        [info setValue:info[@"currentPackage"] forKey:@"previousPackage"];
    }
    
    [info setValue:packageHash forKey:@"currentPackage"];

    [self updateCurrentPackageInfo:info
                             error:error];
}

+ (void)rollbackPackage
{
    NSError *error;
    NSMutableDictionary *info = [self getCurrentPackageInfo];
    NSString *currentPackageFolderPath = [self getCurrentPackageFolderPath];
    if (!info || !currentPackageFolderPath) {
        return;
    }
    
    NSError *deleteError;
    [[NSFileManager defaultManager] removeItemAtPath:currentPackageFolderPath
                                               error:&deleteError];
    if (deleteError) {
        NSLog(@"Error deleting current package contents at %@", currentPackageFolderPath);
    }
    
    [info setValue:info[@"previousPackage"] forKey:@"currentPackage"];
    [info removeObjectForKey:@"previousPackage"];
    
    [self updateCurrentPackageInfo:info error:&error];
}

+ (void)downloadAndReplaceCurrentBundle:(NSString *)remoteBundleUrl
{
    NSURL *urlRequest = [NSURL URLWithString:remoteBundleUrl];
    NSError *error = nil;
    NSString *downloadedBundle = [NSString stringWithContentsOfURL:urlRequest
                                                          encoding:NSUTF8StringEncoding
                                                             error:&error];
    
    if (error) {
        NSLog(@"Error downloading from URL %@", remoteBundleUrl);
    } else {
        NSString *currentPackageBundlePath = [self getCurrentPackageBundlePath];
        if (currentPackageBundlePath) {
            [downloadedBundle writeToFile:currentPackageBundlePath
                               atomically:YES
                                 encoding:NSUTF8StringEncoding
                                    error:&error];
        }
    }
}

+ (void)clearUpdates
{
    [[NSFileManager defaultManager] removeItemAtPath:[self getCodePushPath] error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:[self getStatusFilePath] error:nil];
}

@end
