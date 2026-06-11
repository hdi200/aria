//
//  MuseScorePackageBridge.h
//  MuseReaderiOS
//
//  Created on 4/13/26.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const MSRBridgeErrorDomain;

typedef NS_ERROR_ENUM(MSRBridgeErrorDomain, MSRBridgeErrorCode) {
    MSRBridgeErrorCodeUnsupportedFormat = 1,
    MSRBridgeErrorCodeUnreadableFile = 2,
    MSRBridgeErrorCodeInvalidArchive = 3,
    MSRBridgeErrorCodeMissingScoreFile = 4,
    MSRBridgeErrorCodeInvalidScoreEncoding = 5,
    MSRBridgeErrorCodeRenderCoreUnavailable = 6,
    MSRBridgeErrorCodeRenderCoreFailure = 7,
};

typedef NS_ENUM(NSInteger, MSRDocumentFormat) {
    MSRDocumentFormatMSCZ,
    MSRDocumentFormatMSCX,
    MSRDocumentFormatMXL,
    MSRDocumentFormatMusicXML,
};

@interface MSRPreviewAsset : NSObject

@property (nonatomic, copy, readonly) NSString *path;
@property (nonatomic, copy, readonly) NSData *imageData;

- (instancetype)initWithPath:(NSString *)path
                   imageData:(NSData *)imageData NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface MSRDocumentPayload : NSObject

@property (nonatomic, readonly) MSRDocumentFormat format;
@property (nonatomic, copy, readonly) NSString *rootFilePath;
@property (nonatomic, copy, readonly) NSString *scoreXML;
@property (nonatomic, copy, readonly) NSArray<NSString *> *packageEntries;
@property (nonatomic, copy, readonly) NSArray<MSRPreviewAsset *> *previewAssets;
@property (nonatomic, copy, readonly, nullable) NSData *thumbnailData;

- (instancetype)initWithFormat:(MSRDocumentFormat)format
                  rootFilePath:(NSString *)rootFilePath
                      scoreXML:(NSString *)scoreXML
                 packageEntries:(NSArray<NSString *> *)packageEntries
                  previewAssets:(NSArray<MSRPreviewAsset *> *)previewAssets
                  thumbnailData:(nullable NSData *)thumbnailData NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface MuseScorePackageBridge : NSObject

- (nullable MSRDocumentPayload *)loadDocumentAtURL:(NSURL *)url error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
