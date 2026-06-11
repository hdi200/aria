//
//  MuseScorePackageBridge.mm
//  MuseReaderiOS
//
//  Created on 4/13/26.
//

#import "MuseScorePackageBridge.h"

#import "MSRZipArchive.hpp"

NSErrorDomain const MSRBridgeErrorDomain = @"MuseReaderiOS.Bridge";

namespace {

NSString *const MSRContainerPath = @"META-INF/container.xml";

NSArray<NSString *> *PreferredThumbnailPaths()
{
    return @[
        @"Thumbnails/thumbnail.png",
        @"Thumbnails/thumbnail.jpg",
        @"Thumbnails/thumbnail.jpeg",
        @"thumbnail.png",
        @"thumbnail.jpg",
        @"thumbnail.jpeg",
        @"preview.png",
        @"preview.jpg",
        @"preview.jpeg",
    ];
}

NSString * _Nullable StringFromUTF8Data(NSData *data)
{
    if (!data) {
        return nil;
    }

    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (string) {
        return string;
    }

    return [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
}

NSArray<NSString *> *SortedEntries(const std::vector<std::string>& entries)
{
    NSMutableArray<NSString *> *result = [[NSMutableArray alloc] initWithCapacity:entries.size()];
    for (const std::string& entry : entries) {
        [result addObject:[NSString stringWithUTF8String:entry.c_str()]];
    }

    return [result sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

NSString * _Nullable FirstCaptureGroup(NSString *pattern, NSString *source)
{
    NSError *error = nil;
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionDotMatchesLineSeparators error:&error];
    if (!expression || error) {
        return nil;
    }

    NSTextCheckingResult *match = [expression firstMatchInString:source options:0 range:NSMakeRange(0, source.length)];
    if (!match || match.numberOfRanges < 2) {
        return nil;
    }

    NSRange groupRange = [match rangeAtIndex:1];
    if (groupRange.location == NSNotFound) {
        return nil;
    }

    return [source substringWithRange:groupRange];
}

BOOL IsMusicXMLPathExtension(NSString *pathExtension);

NSString * _Nullable RootScorePathFromContainer(NSString *containerXML, BOOL includeMusicXML)
{
    NSString *rootFilePath = FirstCaptureGroup(@"full-path=\"([^\"]+)\"", containerXML);
    if (!rootFilePath) {
        return nil;
    }

    NSString *pathExtension = rootFilePath.pathExtension.lowercaseString;
    if ([pathExtension isEqualToString:@"mscx"] || (includeMusicXML && IsMusicXMLPathExtension(pathExtension))) {
        return rootFilePath;
    }

    return nil;
}

BOOL IsMusicXMLPathExtension(NSString *pathExtension)
{
    NSString *lowercasedExtension = pathExtension.lowercaseString;
    return [lowercasedExtension isEqualToString:@"musicxml"]
        || [lowercasedExtension isEqualToString:@"xml"];
}

BOOL IsMusicXMLDocument(NSString *xml)
{
    return FirstCaptureGroup(@"<\\s*(score-partwise|score-timewise)\\b", xml) != nil;
}

NSString * _Nullable RootScorePathFromEntries(NSArray<NSString *> *entries, BOOL includeMusicXML)
{
    for (NSString *entry in entries) {
        if ([[entry.pathExtension lowercaseString] isEqualToString:@"mscx"]) {
            return entry;
        }
    }

    if (includeMusicXML) {
        for (NSString *entry in entries) {
            if ([entry isEqualToString:MSRContainerPath]) {
                continue;
            }

            if (IsMusicXMLPathExtension(entry.pathExtension)) {
                return entry;
            }
        }
    }

    return nil;
}

NSData * _Nullable DataForEntry(msr::ZipArchive& archive, NSString *entryPath, NSError **error)
{
    std::string errorMessage;
    std::vector<std::uint8_t> output;

    if (!archive.extract(entryPath.UTF8String, output, errorMessage)) {
        if (error) {
            *error = [NSError errorWithDomain:MSRBridgeErrorDomain code:MSRBridgeErrorCodeInvalidArchive userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Could not read archive entry %@: %s", entryPath, errorMessage.c_str()]
            }];
        }
        return nil;
    }

    return [NSData dataWithBytes:output.data() length:output.size()];
}

BOOL HasSupportedPreviewExtension(NSString *entryPath)
{
    NSString *pathExtension = entryPath.pathExtension.lowercaseString;
    return [pathExtension isEqualToString:@"png"]
        || [pathExtension isEqualToString:@"jpg"]
        || [pathExtension isEqualToString:@"jpeg"];
}

NSArray<NSString *> *PreviewPathsFromEntries(NSArray<NSString *> *entries)
{
    NSMutableOrderedSet<NSString *> *previewPaths = [[NSMutableOrderedSet alloc] init];

    for (NSString *preferredPath in PreferredThumbnailPaths()) {
        for (NSString *entry in entries) {
            if ([entry caseInsensitiveCompare:preferredPath] == NSOrderedSame && HasSupportedPreviewExtension(entry)) {
                [previewPaths addObject:entry];
            }
        }
    }

    for (NSString *entry in entries) {
        if ([entry.lowercaseString hasPrefix:@"thumbnails/"] && HasSupportedPreviewExtension(entry)) {
            [previewPaths addObject:entry];
        }
    }

    for (NSString *entry in entries) {
        NSString *lowercasedName = entry.lastPathComponent.lowercaseString;
        if (HasSupportedPreviewExtension(entry)
            && ([lowercasedName containsString:@"thumbnail"] || [lowercasedName containsString:@"preview"])) {
            [previewPaths addObject:entry];
        }
    }

    return [previewPaths.array sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

NSArray<MSRPreviewAsset *> *PreviewAssetsForPaths(msr::ZipArchive& archive, NSArray<NSString *> *previewPaths)
{
    NSMutableArray<MSRPreviewAsset *> *assets = [[NSMutableArray alloc] initWithCapacity:previewPaths.count];

    for (NSString *previewPath in previewPaths) {
        NSData *previewData = DataForEntry(archive, previewPath, nil);
        if (!previewData) {
            continue;
        }

        [assets addObject:[[MSRPreviewAsset alloc] initWithPath:previewPath imageData:previewData]];
    }

    return assets;
}

NSData * _Nullable ThumbnailDataFromAssets(NSArray<MSRPreviewAsset *> *previewAssets)
{
    for (NSString *preferredPath in PreferredThumbnailPaths()) {
        for (MSRPreviewAsset *asset in previewAssets) {
            if ([asset.path caseInsensitiveCompare:preferredPath] == NSOrderedSame) {
                return asset.imageData;
            }
        }
    }

    return previewAssets.firstObject.imageData;
}

} // namespace

@implementation MSRPreviewAsset

- (instancetype)initWithPath:(NSString *)path imageData:(NSData *)imageData
{
    self = [super init];
    if (self) {
        _path = [path copy];
        _imageData = [imageData copy];
    }
    return self;
}

@end

@implementation MSRDocumentPayload

- (instancetype)initWithFormat:(MSRDocumentFormat)format
                  rootFilePath:(NSString *)rootFilePath
                      scoreXML:(NSString *)scoreXML
                 packageEntries:(NSArray<NSString *> *)packageEntries
                  previewAssets:(NSArray<MSRPreviewAsset *> *)previewAssets
                  thumbnailData:(NSData *)thumbnailData
{
    self = [super init];
    if (self) {
        _format = format;
        _rootFilePath = [rootFilePath copy];
        _scoreXML = [scoreXML copy];
        _packageEntries = [packageEntries copy];
        _previewAssets = [previewAssets copy];
        _thumbnailData = [thumbnailData copy];
    }
    return self;
}

@end

@implementation MuseScorePackageBridge

- (MSRDocumentPayload *)loadDocumentAtURL:(NSURL *)url error:(NSError * _Nullable __autoreleasing *)error
{
    NSString *pathExtension = url.pathExtension.lowercaseString;

    if ([pathExtension isEqualToString:@"mscx"] || IsMusicXMLPathExtension(pathExtension)) {
        NSData *scoreData = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error];
        if (!scoreData) {
            return nil;
        }

        NSString *scoreXML = StringFromUTF8Data(scoreData);
        if (!scoreXML) {
            if (error) {
                *error = [NSError errorWithDomain:MSRBridgeErrorDomain code:MSRBridgeErrorCodeInvalidScoreEncoding userInfo:@{
                    NSLocalizedDescriptionKey: @"This MSCX file could not be decoded as text."
                }];
            }
            return nil;
        }

        BOOL isMSCX = [pathExtension isEqualToString:@"mscx"];
        if (!isMSCX && !IsMusicXMLDocument(scoreXML)) {
            if (error) {
                *error = [NSError errorWithDomain:MSRBridgeErrorDomain code:MSRBridgeErrorCodeUnsupportedFormat userInfo:@{
                    NSLocalizedDescriptionKey: @"This XML file is not a score-partwise or score-timewise MusicXML document."
                }];
            }
            return nil;
        }

        return [[MSRDocumentPayload alloc] initWithFormat:isMSCX ? MSRDocumentFormatMSCX : MSRDocumentFormatMusicXML
                                             rootFilePath:url.lastPathComponent
                                                 scoreXML:scoreXML
                                            packageEntries:@[]
                                             previewAssets:@[]
                                             thumbnailData:nil];
    }

    BOOL isMSCZ = [pathExtension isEqualToString:@"mscz"];
    BOOL isMXL = [pathExtension isEqualToString:@"mxl"];
    if (!isMSCZ && !isMXL) {
        if (error) {
            *error = [NSError errorWithDomain:MSRBridgeErrorDomain code:MSRBridgeErrorCodeUnsupportedFormat userInfo:@{
                NSLocalizedDescriptionKey: @"Only MSCZ, MSCX, MusicXML, and MXL files are supported right now."
            }];
        }
        return nil;
    }

    NSData *archiveData = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error];
    if (!archiveData) {
        return nil;
    }

    std::vector<std::uint8_t> archiveBytes(
        static_cast<const std::uint8_t *>(archiveData.bytes),
        static_cast<const std::uint8_t *>(archiveData.bytes) + archiveData.length
    );

    msr::ZipArchive archive;
    std::string zipError;
    if (!archive.open(std::move(archiveBytes), zipError)) {
        if (error) {
            *error = [NSError errorWithDomain:MSRBridgeErrorDomain code:MSRBridgeErrorCodeInvalidArchive userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"The score package is invalid: %s", zipError.c_str()]
            }];
        }
        return nil;
    }

    NSArray<NSString *> *entries = SortedEntries(archive.entryNames());
    NSData *containerData = DataForEntry(archive, MSRContainerPath, nil);
    NSString *containerXML = StringFromUTF8Data(containerData);

    NSString *rootScorePath = containerXML ? RootScorePathFromContainer(containerXML, isMXL) : nil;
    if (!rootScorePath) {
        rootScorePath = RootScorePathFromEntries(entries, isMXL);
    }

    if (!rootScorePath) {
        if (error) {
            *error = [NSError errorWithDomain:MSRBridgeErrorDomain code:MSRBridgeErrorCodeMissingScoreFile userInfo:@{
                NSLocalizedDescriptionKey: isMXL ? @"The MXL package does not contain a root MusicXML score." : @"The MSCZ package does not contain a root MSCX score."
            }];
        }
        return nil;
    }

    NSData *scoreData = DataForEntry(archive, rootScorePath, error);
    if (!scoreData) {
        return nil;
    }

    NSString *scoreXML = StringFromUTF8Data(scoreData);
    if (!scoreXML) {
        if (error) {
            *error = [NSError errorWithDomain:MSRBridgeErrorDomain code:MSRBridgeErrorCodeInvalidScoreEncoding userInfo:@{
                NSLocalizedDescriptionKey: @"The root score file in this package could not be decoded as text."
            }];
        }
        return nil;
    }

    if (isMXL && !IsMusicXMLDocument(scoreXML)) {
        if (error) {
            *error = [NSError errorWithDomain:MSRBridgeErrorDomain code:MSRBridgeErrorCodeUnsupportedFormat userInfo:@{
                NSLocalizedDescriptionKey: @"The root file in this MXL package is not a score-partwise or score-timewise MusicXML document."
            }];
        }
        return nil;
    }

    NSArray<NSString *> *previewPaths = PreviewPathsFromEntries(entries);
    NSArray<MSRPreviewAsset *> *previewAssets = PreviewAssetsForPaths(archive, previewPaths);
    NSData *thumbnailData = ThumbnailDataFromAssets(previewAssets);

    return [[MSRDocumentPayload alloc] initWithFormat:isMXL ? MSRDocumentFormatMXL : MSRDocumentFormatMSCZ
                                         rootFilePath:rootScorePath
                                             scoreXML:scoreXML
                                        packageEntries:entries
                                         previewAssets:previewAssets
                                         thumbnailData:thumbnailData];
}

@end
