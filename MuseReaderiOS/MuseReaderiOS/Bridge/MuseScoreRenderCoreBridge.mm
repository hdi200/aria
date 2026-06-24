//
//  MuseScoreRenderCoreBridge.mm
//  MuseReaderiOS
//
//

#import "MuseScoreRenderCoreBridge.h"

#import "MuseScorePackageBridge.h"

#include <cstdint>
#include <memory>

#if defined(__arm64__) || defined(__aarch64__)
#include <arm_acle.h>
#endif

#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
#include "../../../sandbox/engraving/score_render_core.h"
#endif

namespace {

#if !defined(MUSEREADER_USE_SCORE_RENDER_CORE) || !MUSEREADER_USE_SCORE_RENDER_CORE
NSError *UnavailableError(NSString *message)
{
    return [NSError errorWithDomain:MSRBridgeErrorDomain code:MSRBridgeErrorCodeRenderCoreUnavailable userInfo:@{
        NSLocalizedDescriptionKey: message
    }];
}
#endif

NSError *FailureError(NSString *message)
{
    return [NSError errorWithDomain:MSRBridgeErrorDomain code:MSRBridgeErrorCodeRenderCoreFailure userInfo:@{
        NSLocalizedDescriptionKey: message
    }];
}

NSString *FailureMessage(const std::string& errorMessage, NSString *fallback)
{
    return errorMessage.empty() ? fallback : [NSString stringWithUTF8String:errorMessage.c_str()];
}

#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
NSArray<MSRLayoutBreakMarker *> *MakeLayoutBreakMarkers(const std::vector<msr::render::RenderedPage::LayoutBreakMarker>& markers)
{
    NSMutableArray<MSRLayoutBreakMarker *> *output = [[NSMutableArray alloc] initWithCapacity:markers.size()];
    for (const auto& marker : markers) {
        [output addObject:[[MSRLayoutBreakMarker alloc] initWithKind:[NSString stringWithUTF8String:marker.kind.c_str()]
                                                         normalizedX:marker.normalizedX
                                                         normalizedY:marker.normalizedY
                                                     normalizedWidth:marker.normalizedWidth
                                                    normalizedHeight:marker.normalizedHeight]];
    }
    return output;
}

NSData *DataFromBytes(const std::vector<std::uint8_t>& bytes)
{
    if (bytes.empty()) {
        return [NSData data];
    }

    return [NSData dataWithBytes:bytes.data() length:bytes.size()];
}

MSRRenderedPage *MakeRenderedPage(const msr::render::RenderedPage& page)
{
    NSData *imageData = DataFromBytes(page.pngData);
    NSData *pdfData = DataFromBytes(page.pdfData);
    return [[MSRRenderedPage alloc] initWithPageIndex:page.pageIndex
                                           pixelWidth:page.pixelWidth
                                          pixelHeight:page.pixelHeight
                                            imageData:imageData
                                              pdfData:pdfData
                                   layoutBreakMarkers:MakeLayoutBreakMarkers(page.layoutBreakMarkers)];
}

NSArray<MSRScorePartInfo *> *MakeScorePartInfos(const std::vector<msr::render::ScorePartInfo>& parts)
{
    NSMutableArray<MSRScorePartInfo *> *output = [[NSMutableArray alloc] initWithCapacity:parts.size()];
    for (const auto& part : parts) {
        [output addObject:[[MSRScorePartInfo alloc] initWithIndex:part.index
                                                           partID:[NSString stringWithUTF8String:part.partId.c_str()]
                                                             name:[NSString stringWithUTF8String:part.name.c_str()]
                                                          visible:part.visible]];
    }
    return output;
}

MSRPlaybackMeasureRegion *MakePlaybackMeasureRegion(const msr::render::PlaybackMeasureRegion& region)
{
    return [[MSRPlaybackMeasureRegion alloc] initWithMeasureIndex:region.measureIndex
                                                        pageIndex:region.pageIndex
                                                 startTimeSeconds:region.startTimeSeconds
                                                   endTimeSeconds:region.endTimeSeconds
                                                      normalizedX:region.normalizedX
                                                      normalizedY:region.normalizedY
                                                  normalizedWidth:region.normalizedWidth
                                                  normalizedHeight:region.normalizedHeight];
}

MSRScoreCorruptionReport *MakeScoreCorruptionReport(const msr::render::ScoreCorruptionReport& report)
{
    NSMutableArray<MSRScoreCorruptionIssue *> *issues = [[NSMutableArray alloc] initWithCapacity:report.issues.size()];
    NSInteger index = 0;
    for (const auto& issue : report.issues) {
        [issues addObject:[[MSRScoreCorruptionIssue alloc] initWithIndex:index
                                                           measureNumber:issue.measureNumber
                                                               staffIndex:issue.staffIndex
                                                                    voice:issue.voice
                                                               repairable:issue.repairable
                                                                     kind:[NSString stringWithUTF8String:issue.kind.c_str()]
                                                                  message:[NSString stringWithUTF8String:issue.message.c_str()]]];
        index += 1;
    }

    return [[MSRScoreCorruptionReport alloc] initWithCorrupted:report.corrupted
                                                       details:[NSString stringWithUTF8String:report.details.c_str()]
                                                        issues:issues];
}

MSRNoteEntryPreviewInfo *MakeNoteEntryPreviewInfo(const msr::render::NoteEntryPreviewState& previewState)
{
    if (!previewState.hasPreview || previewState.overlayPngData.empty()) {
        return [[MSRNoteEntryPreviewInfo alloc] initWithPageIndex:-1
                                               overlayNormalizedX:0
                                               overlayNormalizedY:0
                                           overlayNormalizedWidth:0
                                          overlayNormalizedHeight:0
                                                overlayPixelWidth:0
                                               overlayPixelHeight:0
                                                 overlayImageData:[NSData data]];
    }

    NSData *overlayImageData = [NSData dataWithBytes:previewState.overlayPngData.data()
                                              length:previewState.overlayPngData.size()];
    return [[MSRNoteEntryPreviewInfo alloc] initWithPageIndex:previewState.pageIndex
                                           overlayNormalizedX:previewState.overlayNormalizedX
                                           overlayNormalizedY:previewState.overlayNormalizedY
                                       overlayNormalizedWidth:previewState.overlayNormalizedWidth
                                      overlayNormalizedHeight:previewState.overlayNormalizedHeight
                                            overlayPixelWidth:previewState.overlayPixelWidth
                                           overlayPixelHeight:previewState.overlayPixelHeight
                                             overlayImageData:overlayImageData];
}

MSRPlaybackAudioData *MakePlaybackAudioData(const msr::render::PlaybackAudioData& audioData)
{
    NSData *samples = [NSData dataWithBytes:audioData.interleavedSamples.data()
                                     length:audioData.interleavedSamples.size() * sizeof(float)];
    return [[MSRPlaybackAudioData alloc] initWithSampleRate:audioData.sampleRate
                                               channelCount:audioData.channelCount
                                            durationSeconds:audioData.durationSeconds
                                  interleavedFloat32Samples:samples];
}

MSRSelectionInfo * _Nullable MakeSelectionInfo(const msr::render::ScoreSelectionState& selectionState)
{
    if (!selectionState.hasSelection) {
        return nil;
    }

    NSMutableArray<NSNumber *> *chordMidiPitches = [NSMutableArray arrayWithCapacity:selectionState.chordMidiPitches.size()];
    for (const int midiPitch : selectionState.chordMidiPitches) {
        [chordMidiPitches addObject:@(midiPitch)];
    }
    NSMutableArray<MSRNormalizedRectInfo *> *highlightRects = [NSMutableArray arrayWithCapacity:selectionState.highlightRects.size()];
    for (const msr::render::NormalizedSelectionRect& rect : selectionState.highlightRects) {
        [highlightRects addObject:[[MSRNormalizedRectInfo alloc] initWithNormalizedX:rect.normalizedX
                                                                         normalizedY:rect.normalizedY
                                                                     normalizedWidth:rect.normalizedWidth
                                                                    normalizedHeight:rect.normalizedHeight]];
    }
    NSMutableArray<MSRNormalizedPointInfo *> *attachmentTargets = [NSMutableArray arrayWithCapacity:selectionState.attachmentTargets.size()];
    for (const msr::render::NormalizedPoint& point : selectionState.attachmentTargets) {
        [attachmentTargets addObject:[[MSRNormalizedPointInfo alloc] initWithNormalizedX:point.normalizedX
                                                                            normalizedY:point.normalizedY]];
    }
    NSData *overlayImageData = DataFromBytes(selectionState.overlayPngData);
    NSData *overlayPdfData = DataFromBytes(selectionState.overlayPdfData);

    MSRSelectionInfo *selectionInfo = [[MSRSelectionInfo alloc] initWithPageIndex:selectionState.pageIndex
                                                isNote:selectionState.isNote
                                                isRest:selectionState.isRest
                                                   isBar:selectionState.isBar
                                               isMeasure:selectionState.isMeasure
                                                isSingleMeasure:selectionState.isSingleMeasure
                                         isTimeSignature:selectionState.isTimeSignature
                                                isKeySignature:selectionState.isKeySignature
                                                      isTempo:selectionState.isTempo
                                               isLayoutBreak:selectionState.isLayoutBreak
                                              layoutBreakType:[NSString stringWithUTF8String:selectionState.layoutBreakType.c_str()]
                                       isExpressionSpanner:selectionState.isExpressionSpanner
                                                     isSlur:selectionState.isSlur
                                                      isTie:selectionState.isTie
                                                  isHairpin:selectionState.isHairpin
                                                isEditableText:selectionState.isEditableText
                                            isChordText:selectionState.isChordText
                                        canChangePitch:selectionState.canChangePitch
                                    canFillWithSlashes:selectionState.canFillWithSlashes
                                              isDotted:selectionState.isDotted
                                         isTiedForward:selectionState.isTiedForward
                                           textContent:[NSString stringWithUTF8String:selectionState.textContent.c_str()]
                                             textKind:[NSString stringWithUTF8String:selectionState.textKind.c_str()]
                                             midiPitch:selectionState.midiPitch
                                      chordMidiPitches:chordMidiPitches
                                          playbackBank:selectionState.playbackBank
                                       playbackProgram:selectionState.playbackProgram
                                      playbackSetupData:[NSString stringWithUTF8String:selectionState.playbackSetupData.c_str()]
                            supportsBowingArticulations:selectionState.supportsBowingArticulations
                                          durationCode:selectionState.durationCode
                                        accidentalKind:selectionState.accidentalKind
                                          diatonicStep:selectionState.diatonicStep
                                            currentKey:selectionState.currentKey
                         currentTimeSignatureNumerator:selectionState.currentTimeSignatureNumerator
                       currentTimeSignatureDenominator:selectionState.currentTimeSignatureDenominator
                                             normalizedX:selectionState.normalizedX
                                             normalizedY:selectionState.normalizedY
                                         normalizedWidth:selectionState.normalizedWidth
                                        normalizedHeight:selectionState.normalizedHeight
                                       actionNormalizedX:selectionState.actionNormalizedX
                                       actionNormalizedY:selectionState.actionNormalizedY
                                   actionNormalizedWidth:selectionState.actionNormalizedWidth
                                  actionNormalizedHeight:selectionState.actionNormalizedHeight
                                  startHandleNormalizedX:selectionState.startHandleNormalizedX
                                  startHandleNormalizedY:selectionState.startHandleNormalizedY
                                    endHandleNormalizedX:selectionState.endHandleNormalizedX
                                    endHandleNormalizedY:selectionState.endHandleNormalizedY
                                      hasAttachmentPoint:selectionState.hasAttachmentPoint
                                    attachmentNormalizedX:selectionState.attachmentNormalizedX
                                    attachmentNormalizedY:selectionState.attachmentNormalizedY
                                        attachmentTargets:attachmentTargets
                                            highlightRects:highlightRects
                                      overlayNormalizedX:selectionState.overlayNormalizedX
                                      overlayNormalizedY:selectionState.overlayNormalizedY
                                  overlayNormalizedWidth:selectionState.overlayNormalizedWidth
                                 overlayNormalizedHeight:selectionState.overlayNormalizedHeight
                                      overlayPixelWidth:selectionState.overlayPixelWidth
                                     overlayPixelHeight:selectionState.overlayPixelHeight
                                        overlayImageData:overlayImageData
                                          overlayPdfData:overlayPdfData];
    selectionInfo.isFirstMeasure = selectionState.isFirstMeasure;
    selectionInfo.isPickupMeasure = selectionState.isPickupMeasure;
    selectionInfo.pickupActualNumerator = selectionState.pickupActualNumerator;
    selectionInfo.pickupActualDenominator = selectionState.pickupActualDenominator;
    selectionInfo.pickupNominalNumerator = selectionState.pickupNominalNumerator;
    selectionInfo.pickupNominalDenominator = selectionState.pickupNominalDenominator;
    return selectionInfo;
}

MSRPickupMeasureInfo *MakePickupMeasureInfo(const msr::render::PickupMeasureState& pickupState)
{
    return [[MSRPickupMeasureInfo alloc] initWithIsPickup:pickupState.isPickup
                                          actualNumerator:pickupState.actualNumerator
                                        actualDenominator:pickupState.actualDenominator
                                         nominalNumerator:pickupState.nominalNumerator
                                       nominalDenominator:pickupState.nominalDenominator];
}

MSREditState *MakeEditState(const msr::render::ScoreEditState& editState)
{
    return [[MSREditState alloc] initWithSelection:MakeSelectionInfo(editState.selection)
                                  noteInputEnabled:editState.noteInputEnabled
                             noteInputInsertsRests:editState.noteInputInsertsRests
                                  noteInputIsDotted:editState.noteInputIsDotted
                                      durationCode:editState.durationCode
                                      currentVoice:editState.currentVoice
                                           canUndo:editState.canUndo
                                           canRedo:editState.canRedo
                         activeStaffIsPercussion:editState.activeStaffIsPercussion
                            createMultiMeasureRests:editState.createMultiMeasureRests
                                     hideEmptyStaves:editState.hideEmptyStaves
                             pageWidthMillimeters:editState.pageWidthMillimeters
                            pageHeightMillimeters:editState.pageHeightMillimeters
                            pageMarginMillimeters:editState.pageMarginMillimeters
                             staffSizeMillimeters:editState.staffSizeMillimeters
                             staffSpacingSpatium:editState.staffSpacingSpatium
                             systemSpacingSpatium:editState.systemSpacingSpatium];
}
#endif

} // namespace

@implementation MSRLayoutBreakMarker

- (instancetype)initWithKind:(NSString *)kind
                 normalizedX:(double)normalizedX
                 normalizedY:(double)normalizedY
             normalizedWidth:(double)normalizedWidth
            normalizedHeight:(double)normalizedHeight
{
    self = [super init];
    if (self) {
        _kind = [kind copy];
        _normalizedX = normalizedX;
        _normalizedY = normalizedY;
        _normalizedWidth = normalizedWidth;
        _normalizedHeight = normalizedHeight;
    }
    return self;
}

@end

@implementation MSRRenderedPage

- (instancetype)initWithPageIndex:(NSInteger)pageIndex
                       pixelWidth:(NSInteger)pixelWidth
                      pixelHeight:(NSInteger)pixelHeight
                        imageData:(NSData *)imageData
                           pdfData:(NSData *)pdfData
                layoutBreakMarkers:(NSArray<MSRLayoutBreakMarker *> *)layoutBreakMarkers
{
    self = [super init];
    if (self) {
        _pageIndex = pageIndex;
        _pixelWidth = pixelWidth;
        _pixelHeight = pixelHeight;
        _imageData = [imageData copy];
        _pdfData = [pdfData copy];
        _layoutBreakMarkers = [layoutBreakMarkers copy];
    }
    return self;
}

@end

@implementation MSRScorePartInfo

- (instancetype)initWithIndex:(NSInteger)index
                       partID:(NSString *)partID
                         name:(NSString *)name
                      visible:(BOOL)visible
{
    self = [super init];
    if (self) {
        _index = index;
        _partID = [partID copy];
        _name = [name copy];
        _visible = visible;
    }
    return self;
}

@end

@implementation MSRNoteEntryPreviewInfo

- (instancetype)initWithPageIndex:(NSInteger)pageIndex
               overlayNormalizedX:(double)overlayNormalizedX
               overlayNormalizedY:(double)overlayNormalizedY
           overlayNormalizedWidth:(double)overlayNormalizedWidth
          overlayNormalizedHeight:(double)overlayNormalizedHeight
                 overlayPixelWidth:(NSInteger)overlayPixelWidth
                overlayPixelHeight:(NSInteger)overlayPixelHeight
                  overlayImageData:(NSData *)overlayImageData
{
    self = [super init];
    if (self) {
        _pageIndex = pageIndex;
        _overlayNormalizedX = overlayNormalizedX;
        _overlayNormalizedY = overlayNormalizedY;
        _overlayNormalizedWidth = overlayNormalizedWidth;
        _overlayNormalizedHeight = overlayNormalizedHeight;
        _overlayPixelWidth = overlayPixelWidth;
        _overlayPixelHeight = overlayPixelHeight;
        _overlayImageData = [overlayImageData copy];
    }
    return self;
}

@end

@implementation MSRNormalizedRectInfo

- (instancetype)initWithNormalizedX:(double)normalizedX
                         normalizedY:(double)normalizedY
                     normalizedWidth:(double)normalizedWidth
                    normalizedHeight:(double)normalizedHeight
{
    self = [super init];
    if (self) {
        _normalizedX = normalizedX;
        _normalizedY = normalizedY;
        _normalizedWidth = normalizedWidth;
        _normalizedHeight = normalizedHeight;
    }
    return self;
}

@end

@implementation MSRNormalizedPointInfo

- (instancetype)initWithNormalizedX:(double)normalizedX
                          normalizedY:(double)normalizedY
{
    self = [super init];
    if (self) {
        _normalizedX = normalizedX;
        _normalizedY = normalizedY;
    }
    return self;
}

@end

@implementation MSRSelectionInfo

- (instancetype)initWithPageIndex:(NSInteger)pageIndex
                           isNote:(BOOL)isNote
                            isRest:(BOOL)isRest
                            isBar:(BOOL)isBar
                        isMeasure:(BOOL)isMeasure
                    isSingleMeasure:(BOOL)isSingleMeasure
                   isTimeSignature:(BOOL)isTimeSignature
                 isKeySignature:(BOOL)isKeySignature
                         isTempo:(BOOL)isTempo
                   isLayoutBreak:(BOOL)isLayoutBreak
                  layoutBreakType:(NSString *)layoutBreakType
          isExpressionSpanner:(BOOL)isExpressionSpanner
                        isSlur:(BOOL)isSlur
                         isTie:(BOOL)isTie
                     isHairpin:(BOOL)isHairpin
                 isEditableText:(BOOL)isEditableText
                        isChordText:(BOOL)isChordText
                   canChangePitch:(BOOL)canChangePitch
                canFillWithSlashes:(BOOL)canFillWithSlashes
                         isDotted:(BOOL)isDotted
                    isTiedForward:(BOOL)isTiedForward
                       textContent:(NSString *)textContent
                        textKind:(NSString *)textKind
                        midiPitch:(NSInteger)midiPitch
                   chordMidiPitches:(NSArray<NSNumber *> *)chordMidiPitches
                  playbackBank:(NSInteger)playbackBank
               playbackProgram:(NSInteger)playbackProgram
              playbackSetupData:(NSString *)playbackSetupData
      supportsBowingArticulations:(BOOL)supportsBowingArticulations
	                  durationCode:(NSInteger)durationCode
	                    accidentalKind:(NSInteger)accidentalKind
	                      diatonicStep:(NSInteger)diatonicStep
	                        currentKey:(NSInteger)currentKey
	         currentTimeSignatureNumerator:(NSInteger)currentTimeSignatureNumerator
	       currentTimeSignatureDenominator:(NSInteger)currentTimeSignatureDenominator
	                         normalizedX:(double)normalizedX
                         normalizedY:(double)normalizedY
                     normalizedWidth:(double)normalizedWidth
                    normalizedHeight:(double)normalizedHeight
                    actionNormalizedX:(double)actionNormalizedX
                    actionNormalizedY:(double)actionNormalizedY
                actionNormalizedWidth:(double)actionNormalizedWidth
               actionNormalizedHeight:(double)actionNormalizedHeight
              startHandleNormalizedX:(double)startHandleNormalizedX
               startHandleNormalizedY:(double)startHandleNormalizedY
                 endHandleNormalizedX:(double)endHandleNormalizedX
                 endHandleNormalizedY:(double)endHandleNormalizedY
                     hasAttachmentPoint:(BOOL)hasAttachmentPoint
                   attachmentNormalizedX:(double)attachmentNormalizedX
                   attachmentNormalizedY:(double)attachmentNormalizedY
                     attachmentTargets:(NSArray<MSRNormalizedPointInfo *> *)attachmentTargets
                          highlightRects:(NSArray<MSRNormalizedRectInfo *> *)highlightRects
                  overlayNormalizedX:(double)overlayNormalizedX
                  overlayNormalizedY:(double)overlayNormalizedY
              overlayNormalizedWidth:(double)overlayNormalizedWidth
             overlayNormalizedHeight:(double)overlayNormalizedHeight
                  overlayPixelWidth:(NSInteger)overlayPixelWidth
                 overlayPixelHeight:(NSInteger)overlayPixelHeight
                    overlayImageData:(NSData *)overlayImageData
                      overlayPdfData:(NSData *)overlayPdfData
{
    self = [super init];
    if (self) {
        _pageIndex = pageIndex;
        _isNote = isNote;
        _isRest = isRest;
        _isBar = isBar;
        _isMeasure = isMeasure;
        _isSingleMeasure = isSingleMeasure;
        _isTimeSignature = isTimeSignature;
        _isKeySignature = isKeySignature;
        _isTempo = isTempo;
        _isLayoutBreak = isLayoutBreak;
        _layoutBreakType = [layoutBreakType copy];
        _isExpressionSpanner = isExpressionSpanner;
        _isSlur = isSlur;
        _isTie = isTie;
        _isHairpin = isHairpin;
        _isEditableText = isEditableText;
        _isChordText = isChordText;
        _canChangePitch = canChangePitch;
        _canFillWithSlashes = canFillWithSlashes;
        _isDotted = isDotted;
        _isTiedForward = isTiedForward;
        _textContent = [textContent copy];
        _textKind = [textKind copy];
        _midiPitch = midiPitch;
        _chordMidiPitches = [chordMidiPitches copy];
        _playbackBank = playbackBank;
        _playbackProgram = playbackProgram;
        _playbackSetupData = [playbackSetupData copy];
        _supportsBowingArticulations = supportsBowingArticulations;
        _durationCode = durationCode;
        _accidentalKind = accidentalKind;
        _diatonicStep = diatonicStep;
        _currentKey = currentKey;
        _currentTimeSignatureNumerator = currentTimeSignatureNumerator;
        _currentTimeSignatureDenominator = currentTimeSignatureDenominator;
        _normalizedX = normalizedX;
        _normalizedY = normalizedY;
        _normalizedWidth = normalizedWidth;
        _normalizedHeight = normalizedHeight;
        _actionNormalizedX = actionNormalizedX;
        _actionNormalizedY = actionNormalizedY;
        _actionNormalizedWidth = actionNormalizedWidth;
        _actionNormalizedHeight = actionNormalizedHeight;
        _startHandleNormalizedX = startHandleNormalizedX;
        _startHandleNormalizedY = startHandleNormalizedY;
        _endHandleNormalizedX = endHandleNormalizedX;
        _endHandleNormalizedY = endHandleNormalizedY;
        _hasAttachmentPoint = hasAttachmentPoint;
        _attachmentNormalizedX = attachmentNormalizedX;
        _attachmentNormalizedY = attachmentNormalizedY;
        _attachmentTargets = [attachmentTargets copy];
        _highlightRects = [highlightRects copy];
        _overlayNormalizedX = overlayNormalizedX;
        _overlayNormalizedY = overlayNormalizedY;
        _overlayNormalizedWidth = overlayNormalizedWidth;
        _overlayNormalizedHeight = overlayNormalizedHeight;
        _overlayPixelWidth = overlayPixelWidth;
        _overlayPixelHeight = overlayPixelHeight;
        _overlayImageData = [overlayImageData copy];
        _overlayPdfData = [overlayPdfData copy];
    }
    return self;
}

@end

@implementation MSRPickupMeasureInfo

- (instancetype)initWithIsPickup:(BOOL)isPickup
                  actualNumerator:(NSInteger)actualNumerator
                actualDenominator:(NSInteger)actualDenominator
                 nominalNumerator:(NSInteger)nominalNumerator
               nominalDenominator:(NSInteger)nominalDenominator
{
    self = [super init];
    if (self) {
        _isPickup = isPickup;
        _actualNumerator = actualNumerator;
        _actualDenominator = actualDenominator;
        _nominalNumerator = nominalNumerator;
        _nominalDenominator = nominalDenominator;
    }
    return self;
}

@end

@implementation MSREditState

- (instancetype)initWithSelection:(MSRSelectionInfo * _Nullable)selection
                 noteInputEnabled:(BOOL)noteInputEnabled
            noteInputInsertsRests:(BOOL)noteInputInsertsRests
                  noteInputIsDotted:(BOOL)noteInputIsDotted
                     durationCode:(NSInteger)durationCode
                     currentVoice:(NSInteger)currentVoice
                          canUndo:(BOOL)canUndo
                          canRedo:(BOOL)canRedo
         activeStaffIsPercussion:(BOOL)activeStaffIsPercussion
           createMultiMeasureRests:(BOOL)createMultiMeasureRests
                    hideEmptyStaves:(BOOL)hideEmptyStaves
             pageWidthMillimeters:(double)pageWidthMillimeters
            pageHeightMillimeters:(double)pageHeightMillimeters
            pageMarginMillimeters:(double)pageMarginMillimeters
             staffSizeMillimeters:(double)staffSizeMillimeters
             staffSpacingSpatium:(double)staffSpacingSpatium
             systemSpacingSpatium:(double)systemSpacingSpatium
{
    self = [super init];
    if (self) {
        _selection = selection;
        _noteInputEnabled = noteInputEnabled;
        _noteInputInsertsRests = noteInputInsertsRests;
        _noteInputIsDotted = noteInputIsDotted;
        _durationCode = durationCode;
        _currentVoice = currentVoice;
        _canUndo = canUndo;
        _canRedo = canRedo;
        _activeStaffIsPercussion = activeStaffIsPercussion;
        _createMultiMeasureRests = createMultiMeasureRests;
        _hideEmptyStaves = hideEmptyStaves;
        _pageWidthMillimeters = pageWidthMillimeters;
        _pageHeightMillimeters = pageHeightMillimeters;
        _pageMarginMillimeters = pageMarginMillimeters;
        _staffSizeMillimeters = staffSizeMillimeters;
        _staffSpacingSpatium = staffSpacingSpatium;
        _systemSpacingSpatium = systemSpacingSpatium;
    }
    return self;
}

@end

@implementation MSRRenderedDocument

- (instancetype)initWithTotalPageCount:(NSInteger)totalPageCount
                                 pages:(NSArray<MSRRenderedPage *> *)pages
{
    self = [super init];
    if (self) {
        _totalPageCount = totalPageCount;
        _pages = [pages copy];
    }
    return self;
}

@end

@implementation MSRPlaybackMeasureRegion

- (instancetype)initWithMeasureIndex:(NSInteger)measureIndex
                           pageIndex:(NSInteger)pageIndex
                    startTimeSeconds:(NSTimeInterval)startTimeSeconds
                      endTimeSeconds:(NSTimeInterval)endTimeSeconds
                         normalizedX:(double)normalizedX
                         normalizedY:(double)normalizedY
                     normalizedWidth:(double)normalizedWidth
                    normalizedHeight:(double)normalizedHeight
{
    self = [super init];
    if (self) {
        _measureIndex = measureIndex;
        _pageIndex = pageIndex;
        _startTimeSeconds = startTimeSeconds;
        _endTimeSeconds = endTimeSeconds;
        _normalizedX = normalizedX;
        _normalizedY = normalizedY;
        _normalizedWidth = normalizedWidth;
        _normalizedHeight = normalizedHeight;
    }
    return self;
}

@end

@implementation MSRScoreCorruptionIssue

- (instancetype)initWithIndex:(NSInteger)index
                measureNumber:(NSInteger)measureNumber
                    staffIndex:(NSInteger)staffIndex
                         voice:(NSInteger)voice
                    repairable:(BOOL)repairable
                          kind:(NSString *)kind
                       message:(NSString *)message
{
    self = [super init];
    if (self) {
        _index = index;
        _measureNumber = measureNumber;
        _staffIndex = staffIndex;
        _voice = voice;
        _repairable = repairable;
        _kind = [kind copy];
        _message = [message copy];
    }
    return self;
}

@end

@implementation MSRScoreCorruptionReport

- (instancetype)initWithCorrupted:(BOOL)corrupted
                           details:(NSString *)details
                            issues:(NSArray<MSRScoreCorruptionIssue *> *)issues
{
    self = [super init];
    if (self) {
        _corrupted = corrupted;
        _details = [details copy];
        _issues = [issues copy];
    }
    return self;
}

@end

@implementation MSRPlaybackAudioData

- (instancetype)initWithSampleRate:(NSInteger)sampleRate
                       channelCount:(NSInteger)channelCount
                    durationSeconds:(NSTimeInterval)durationSeconds
          interleavedFloat32Samples:(NSData *)interleavedFloat32Samples
{
    self = [super init];
    if (self) {
        _sampleRate = sampleRate;
        _channelCount = channelCount;
        _durationSeconds = durationSeconds;
        _interleavedFloat32Samples = [interleavedFloat32Samples copy];
    }
    return self;
}

@end

@interface MSRRenderSession ()

#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
- (instancetype)initWithSession:(std::unique_ptr<msr::render::ScoreRenderSession>)session
                 totalPageCount:(NSInteger)totalPageCount
               supportsPlayback:(BOOL)supportsPlayback
                supportsEditing:(BOOL)supportsEditing;
#endif

@end

@implementation MSRRenderSession
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    std::unique_ptr<msr::render::ScoreRenderSession> _session;
#endif
}

#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
- (instancetype)initWithSession:(std::unique_ptr<msr::render::ScoreRenderSession>)session
                 totalPageCount:(NSInteger)totalPageCount
               supportsPlayback:(BOOL)supportsPlayback
                supportsEditing:(BOOL)supportsEditing
{
    self = [super init];
    if (self) {
        _session = std::move(session);
        _totalPageCount = totalPageCount;
        _supportsPlayback = supportsPlayback;
        _supportsEditing = supportsEditing;
    }
    return self;
}
#endif

- (MSRRenderedPage *)renderPageAtIndex:(NSInteger)pageIndex
                                   dpi:(NSInteger)dpi
                                 error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::RenderedPage renderedPage;
    std::string errorMessage;
    if (!_session->renderPage(static_cast<int>(pageIndex), static_cast<int>(dpi), renderedPage, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not render this page."));
        }
        return nil;
    }

    return MakeRenderedPage(renderedPage);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to the reusable MuseScore render core yet, so it cannot request live page images from the score engine.");
    }
    return nil;
#endif
}

- (BOOL)setActivePartIndex:(NSInteger)partIndex
            totalPageCount:(NSInteger *)totalPageCount
                     error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return NO;
    }

    int updatedPageCount = 0;
    std::string errorMessage;
    if (!_session->setActivePartIndex(static_cast<int>(partIndex), updatedPageCount, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not open that part."));
        }
        return NO;
    }

    _totalPageCount = updatedPageCount;
    if (totalPageCount) {
        *totalPageCount = updatedPageCount;
    }
    return YES;
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to the reusable MuseScore render core yet, so it cannot switch parts.");
    }
    return NO;
#endif
}

- (BOOL)setFullScoreViewWithTotalPageCount:(NSInteger *)totalPageCount
                                      error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return NO;
    }

    int updatedPageCount = 0;
    std::string errorMessage;
    if (!_session->setActivePartIndex(std::nullopt, updatedPageCount, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not return to the full score."));
        }
        return NO;
    }

    _totalPageCount = updatedPageCount;
    if (totalPageCount) {
        *totalPageCount = updatedPageCount;
    }
    return YES;
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to the reusable MuseScore render core yet, so it cannot switch parts.");
    }
    return NO;
#endif
}

- (BOOL)concertPitchEnabled
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    return _session ? _session->concertPitchEnabled() : NO;
#else
    return NO;
#endif
}

- (BOOL)hasConcertPitchRelevantTransposition
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    return _session ? _session->hasConcertPitchRelevantTransposition() : NO;
#else
    return NO;
#endif
}

- (NSArray<MSRScorePartInfo *> *)scoreParts
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    return _session ? MakeScorePartInfos(_session->partInfoList()) : @[];
#else
    return @[];
#endif
}

- (BOOL)setConcertPitchEnabled:(BOOL)enabled
                totalPageCount:(NSInteger *)totalPageCount
                          error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return NO;
    }

    int updatedPageCount = 0;
    std::string errorMessage;
    if (!_session->setConcertPitchEnabled(enabled, updatedPageCount, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not change concert pitch."));
        }
        return NO;
    }

    _totalPageCount = updatedPageCount;
    if (totalPageCount) {
        *totalPageCount = updatedPageCount;
    }
    return YES;
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to the reusable MuseScore render core yet, so it cannot change concert pitch.");
    }
    return NO;
#endif
}

- (BOOL)refreshTotalPageCount:(NSInteger *)totalPageCount
                         error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return NO;
    }

    const NSInteger updatedPageCount = _session->totalPageCount();
    _totalPageCount = updatedPageCount;
    if (totalPageCount) {
        *totalPageCount = updatedPageCount;
    }
    return YES;
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to the reusable MuseScore render core yet, so it cannot refresh the page count.");
    }
    return NO;
#endif
}

- (NSData *)playbackMIDIDataWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    std::vector<std::uint8_t> midiData;
    std::string errorMessage;
    if (!_session->playbackMIDIData(midiData, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not export playback MIDI."));
        }
        return nil;
    }

    return [NSData dataWithBytes:midiData.data() length:midiData.size()];
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore playback support yet.");
    }
    return nil;
#endif
}

- (NSData *)pdfDataWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    std::vector<std::uint8_t> pdfData;
    std::string errorMessage;
    if (!_session->pdfData(pdfData, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not export PDF."));
        }
        return nil;
    }

    return [NSData dataWithBytes:pdfData.data() length:pdfData.size()];
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore PDF export support yet.");
    }
    return nil;
#endif
}

- (NSData *)musicXMLDataWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    std::vector<std::uint8_t> musicXMLData;
    std::string errorMessage;
    if (!_session->musicXMLData(musicXMLData, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not export MusicXML."));
        }
        return nil;
    }

    return [NSData dataWithBytes:musicXMLData.data() length:musicXMLData.size()];
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore MusicXML export support yet.");
    }
    return nil;
#endif
}

- (MSRPlaybackAudioData *)playbackEventAudioDataWithSoundFontPath:(NSString *)soundFontPath
                                                 startTimeSeconds:(NSTimeInterval)startTimeSeconds
                                                  durationSeconds:(NSTimeInterval)durationSeconds
                                                metronomeEnabled:(BOOL)metronomeEnabled
                                                             error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::PlaybackAudioData audioData;
    std::string errorMessage;
    if (!_session->playbackEventAudioData(soundFontPath.UTF8String ?: "",
                                           startTimeSeconds,
                                           durationSeconds,
                                           metronomeEnabled,
                                           audioData,
                                           errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not render event-driven playback audio."));
        }
        return nil;
    }

    return MakePlaybackAudioData(audioData);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore playback event audio support yet.");
    }
    return nil;
#endif
}

- (NSArray<MSRPlaybackMeasureRegion *> *)playbackMeasureRegionsWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    std::vector<msr::render::PlaybackMeasureRegion> playbackRegions;
    std::string errorMessage;
    if (!_session->playbackMeasureRegions(playbackRegions, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not resolve playback measure regions."));
        }
        return nil;
    }

    NSMutableArray<MSRPlaybackMeasureRegion *> *regions = [[NSMutableArray alloc] initWithCapacity:playbackRegions.size()];
    for (const auto& region : playbackRegions) {
        [regions addObject:MakePlaybackMeasureRegion(region)];
    }

    return regions;
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore playback region support yet.");
    }
    return nil;
#endif
}

- (MSRScoreCorruptionReport *)scoreCorruptionReportWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreCorruptionReport report;
    std::string errorMessage;
    if (!_session->scoreCorruptionReport(report, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not inspect score corruption."));
        }
        return nil;
    }

    return MakeScoreCorruptionReport(report);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore corruption inspection yet.");
    }
    return nil;
#endif
}

- (MSREditState *)selectCorruptionIssueAtIndex:(NSInteger)index
                                         error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->selectCorruptionIssue(static_cast<int>(index), editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not select that corrupted bar."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore corruption repair yet.");
    }
    return nil;
#endif
}

- (MSRScoreCorruptionReport *)clearCorruptionIssueAtIndex:(NSInteger)index
                                                editState:(MSREditState * _Nullable __autoreleasing *)editState
                                                    error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState coreEditState;
    msr::render::ScoreCorruptionReport report;
    std::string errorMessage;
    if (!_session->clearCorruptionIssue(static_cast<int>(index), coreEditState, report, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not clear that corrupted bar."));
        }
        return nil;
    }

    if (editState) {
        *editState = MakeEditState(coreEditState);
    }
    return MakeScoreCorruptionReport(report);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore corruption repair yet.");
    }
    return nil;
#endif
}

- (MSREditState *)currentEditStateWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->currentEditState(editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not resolve the current edit state."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)selectElementAtPageIndex:(NSInteger)pageIndex
                               normalizedX:(double)normalizedX
                               normalizedY:(double)normalizedY
                            hitRadiusScale:(double)hitRadiusScale
                                     error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->selectElement(static_cast<int>(pageIndex), normalizedX, normalizedY, hitRadiusScale, editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not select an item at that location."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)selectMeasureRangeAtPageIndex:(NSInteger)pageIndex
                               startNormalizedX:(double)startNormalizedX
                               startNormalizedY:(double)startNormalizedY
                                 endNormalizedX:(double)endNormalizedX
                                 endNormalizedY:(double)endNormalizedY
                                          error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->selectMeasureRange(static_cast<int>(pageIndex),
                                      startNormalizedX,
                                      startNormalizedY,
                                      endNormalizedX,
                                      endNormalizedY,
                                      editState,
                                      errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not select that measure range."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)previewMeasureRangeAtPageIndex:(NSInteger)pageIndex
                                startNormalizedX:(double)startNormalizedX
                                startNormalizedY:(double)startNormalizedY
                                  endNormalizedX:(double)endNormalizedX
                                  endNormalizedY:(double)endNormalizedY
                                           error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->previewMeasureRange(static_cast<int>(pageIndex),
                                       startNormalizedX,
                                       startNormalizedY,
                                       endNormalizedX,
                                       endNormalizedY,
                                       editState,
                                       errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not preview that measure range."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)setNoteInputEnabled:(BOOL)enabled
                                error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->setNoteInputEnabled(enabled, editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not update note input."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)setCurrentVoice:(NSInteger)voice
                            error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->setCurrentVoice(static_cast<int>(voice), editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not update the current voice."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)applyDurationCode:(NSInteger)durationCode
                              error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->applyDuration(static_cast<int>(durationCode), editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not change the duration."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)toggleRestWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->toggleRest(editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not toggle rest mode."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)enterRestAtCursorWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->enterRestAtCursor(editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not enter a rest at the cursor."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)toggleDotWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->toggleDot(editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not toggle the augmentation dot."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)toggleTieWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->toggleTie(editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not toggle the tie."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)addTuplet:(NSInteger)tupletCount
                      error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->addTuplet(static_cast<int>(tupletCount), editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not add that tuplet."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)addText:(NSString *)textKind
                    error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->addText(textKind.UTF8String ?: "", editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not add that text."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)selectAttachedChordTextWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->selectAttachedChordText(editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not select the attached chord text."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)selectAttachedLyricsWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->selectAttachedLyrics(editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not select the attached lyrics."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)setSelectedText:(NSString *)text
                             error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->setSelectedText(text.UTF8String ?: "", editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not edit that text."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)addLyricsText:(NSString *)text
            advanceToNextChord:(BOOL)advanceToNextChord
                          error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->addLyricsText(text.UTF8String ?: "", advanceToNextChord, editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not edit lyrics."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)addRepeatJump:(NSString *)repeatJumpKind
                          error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->addRepeatJump(repeatJumpKind.UTF8String ?: "", editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not add that repeat or jump."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)addExpression:(NSString *)expressionKind
                          error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->addExpression(expressionKind.UTF8String ?: "", editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not add that expression."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)retargetSelectedExpressionEndpointAtStart:(BOOL)startEndpoint
                                                  pageIndex:(NSInteger)pageIndex
                                                normalizedX:(double)normalizedX
                                                normalizedY:(double)normalizedY
                                                      error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->retargetSelectedExpressionEndpoint(startEndpoint,
                                                      static_cast<int>(pageIndex),
                                                      normalizedX,
                                                      normalizedY,
                                                      editState,
                                                      errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not move that expression endpoint."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)dragSelectedChordTextAtPageIndex:(NSInteger)pageIndex
                                       normalizedX:(double)normalizedX
                                       normalizedY:(double)normalizedY
                                             error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->dragSelectedChordText(static_cast<int>(pageIndex),
                                         normalizedX,
                                         normalizedY,
                                         editState,
                                         errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not move that chord symbol."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)addLayoutBreak:(NSString *)breakKind
                           error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->addLayoutBreak(breakKind.UTF8String ?: "", editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not add that layout break."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)removeLayoutBreakWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->removeLayoutBreak(editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not remove that layout break."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)fillSelectionWithSlashesWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->fillSelectionWithSlashes(editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not fill the selection with slashes."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)replaceSelectionWithRhythmicSlashesWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->replaceSelectionWithRhythmicSlashes(editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not replace the selection with rhythmic slash notation."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)applyAutoSystemBreaksWithMeasuresPerSystem:(NSInteger)measuresPerSystem
                                           lockCurrentLayout:(BOOL)lockCurrentLayout
                                              removeExisting:(BOOL)removeExisting
                                                       error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->applyAutoSystemBreaks(static_cast<int>(measuresPerSystem), lockCurrentLayout, removeExisting, editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not apply auto breaks."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)updateStaffSpacing:(double)staffDistanceSpatium
                               error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->updateStaffSpacing(staffDistanceSpatium, editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not update staff spacing."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)updatePageLayoutWithPageWidthMillimeters:(double)pageWidthMillimeters
                                    pageHeightMillimeters:(double)pageHeightMillimeters
                                       marginMillimeters:(double)marginMillimeters
                                   staffSizeMillimeters:(double)staffSizeMillimeters
                                  staffSpacingSpatium:(double)staffSpacingSpatium
                                  systemSpacingSpatium:(double)systemSpacingSpatium
                                                error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->updatePageLayout(pageWidthMillimeters,
                                    pageHeightMillimeters,
                                    marginMillimeters,
                                    staffSizeMillimeters,
                                    staffSpacingSpatium,
                                    systemSpacingSpatium,
                                    editState,
                                    errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not update page settings."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)updateLayoutOptionsWithCreateMultiMeasureRests:(BOOL)createMultiMeasureRests
                                                 hideEmptyStaves:(BOOL)hideEmptyStaves
                                                           error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->updateLayoutOptions(createMultiMeasureRests, hideEmptyStaves, editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not update layout options."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)addTempoWithBeatUnit:(NSString *)beatUnit
                                   bpm:(NSInteger)bpm
                                 error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->addTempo(beatUnit.UTF8String ?: "", static_cast<int>(bpm), editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not add that tempo marking."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)updateTimeSignatureWithNumerator:(NSInteger)numerator
                                       denominator:(NSInteger)denominator
                                        commonTime:(BOOL)commonTime
                                           cutTime:(BOOL)cutTime
                                         fromStart:(BOOL)fromStart
                                             error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }
    if (denominator != 1 && denominator != 2 && denominator != 4 && denominator != 8 && denominator != 16) {
        if (error) {
            *error = FailureError(@"Time signature denominator must be one of 1, 2, 4, 8, or 16.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->updateTimeSignature(static_cast<int>(numerator), static_cast<int>(denominator), commonTime, cutTime, fromStart, editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not update the time signature."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)updateKeySignature:(NSInteger)keyValue
                            fromStart:(BOOL)fromStart
                                error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->updateKeySignature(static_cast<int>(keyValue), fromStart, editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not update the key signature."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)insertNoteAtPageIndex:(NSInteger)pageIndex
                            normalizedX:(double)normalizedX
                            normalizedY:(double)normalizedY
                                  error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->insertNote(static_cast<int>(pageIndex), normalizedX, normalizedY, editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not place a note there."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)insertNoteAtPageIndex:(NSInteger)pageIndex
                            normalizedX:(double)normalizedX
                            normalizedY:(double)normalizedY
                         accidentalKind:(NSInteger)accidentalKind
                                  error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->insertNoteWithAccidental(static_cast<int>(pageIndex), normalizedX, normalizedY, static_cast<int>(accidentalKind), editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not place a note there."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)insertNoteAtPageIndex:(NSInteger)pageIndex
                            normalizedX:(double)normalizedX
                            normalizedY:(double)normalizedY
                             pitchClass:(NSInteger)pitchClass
                            preferFlats:(BOOL)preferFlats
                                  error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->insertNoteWithPitch(static_cast<int>(pageIndex), normalizedX, normalizedY, static_cast<int>(pitchClass), preferFlats, editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not place a note there."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)insertPitchAtCursor:(NSInteger)pitchClass
                          preferFlats:(BOOL)preferFlats
                    addToCurrentChord:(BOOL)addToCurrentChord
                                error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->insertPitchAtCursor(static_cast<int>(pitchClass), preferFlats, addToCurrentChord, editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not enter that pitch at the current cursor."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)insertMIDIPitchAtCursor:(NSInteger)midiPitch
                              preferFlats:(BOOL)preferFlats
                       addToCurrentChord:(BOOL)addToCurrentChord
                                    error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->insertMIDIPitchAtCursor(static_cast<int>(midiPitch), preferFlats, addToCurrentChord, editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not enter that exact pitch at the current cursor."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)insertMIDIChordAtCursor:(NSArray<NSNumber *> *)midiPitches
                              preferFlats:(BOOL)preferFlats
                                     error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    std::vector<int> pitches;
    pitches.reserve(midiPitches.count);
    for (NSNumber *pitch in midiPitches) {
        pitches.push_back(static_cast<int>(pitch.integerValue));
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->insertMIDIChordAtCursor(pitches, preferFlats, editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not enter that MIDI chord at the current cursor."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)removeMIDIPitchFromCurrentChord:(NSInteger)midiPitch
                                            error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->removeMIDIPitchFromCurrentChord(static_cast<int>(midiPitch), editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not remove that note from the chord."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSRNoteEntryPreviewInfo *)noteEntryPreviewAtPageIndex:(NSInteger)pageIndex
                                             normalizedX:(double)normalizedX
                                             normalizedY:(double)normalizedY
                                            durationCode:(NSInteger)durationCode
                                                    rest:(BOOL)rest
                                          accidentalKind:(NSInteger)accidentalKind
                                                   error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::NoteEntryPreviewState previewState;
    std::string errorMessage;
    if (!_session->noteEntryPreview(static_cast<int>(pageIndex),
                                    normalizedX,
                                    normalizedY,
                                    static_cast<int>(durationCode),
                                    rest,
                                    static_cast<int>(accidentalKind),
                                    previewState,
                                    errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not preview note entry there."));
        }
        return nil;
    }

    return MakeNoteEntryPreviewInfo(previewState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)deleteSelectionWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->deleteSelection(editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not delete the selection."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)clearSelectedMeasureWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->clearSelectedMeasure(editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not clear the selected measure."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)removeSelectedMeasureWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->removeSelectedMeasure(editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not remove the selected measure."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)addMeasures:(NSInteger)count
                        error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->addMeasures(static_cast<int>(count), editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not add measures."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)setRegularMeasureCount:(NSInteger)count
                                   error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->setRegularMeasureCount(static_cast<int>(count), editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not set the measure count."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)resetTemplateMeasures:(NSInteger)count
                                  error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->resetTemplateMeasures(static_cast<int>(count), editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not reset the template measures."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSRPickupMeasureInfo *)firstMeasurePickupStateWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::PickupMeasureState pickupState;
    std::string errorMessage;
    if (!_session->firstMeasurePickupState(pickupState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not read the pickup measure."));
        }
        return nil;
    }

    return MakePickupMeasureInfo(pickupState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)setFirstMeasurePickupWithNumerator:(NSInteger)numerator
                                         denominator:(NSInteger)denominator
                                               error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->setFirstMeasurePickup(static_cast<int>(numerator), static_cast<int>(denominator), editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not create the pickup measure."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)createFirstPickupMeasureWithNumerator:(NSInteger)numerator
                                            denominator:(NSInteger)denominator
                                                  error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->createFirstPickupMeasure(static_cast<int>(numerator), static_cast<int>(denominator), editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not create the pickup measure."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)clearFirstMeasurePickupWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->clearFirstMeasurePickup(editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not remove the pickup measure."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)copySelectedMeasureRangeWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->copySelectedMeasureRange(editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not copy the selected measure range."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)cutSelectedMeasureRangeWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->cutSelectedMeasureRange(editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not cut the selected measure range."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)pasteMeasureRangeWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->pasteMeasureRange(editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not paste the copied measure range."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)selectAllWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->selectAll(editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not select the score."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)clearSelectionWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->clearSelection(editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not clear the selection."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)transposeSelectedMeasureRangeWithMode:(NSInteger)mode
                                              direction:(NSInteger)direction
                                               interval:(NSInteger)interval
                                              targetKey:(NSInteger)targetKey
                                                  error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->transposeSelectedMeasureRange(static_cast<int>(mode),
                                                 static_cast<int>(direction),
                                                 static_cast<int>(interval),
                                                 static_cast<int>(targetKey),
                                                 editState,
                                                 errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not transpose the selected measures."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)moveSelectedPitchUpWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->moveSelectionPitch(true, editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not raise the selected pitch."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)moveSelectedPitchDownWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->moveSelectionPitch(false, editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not lower the selected pitch."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)selectPreviousElementWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->selectAdjacentElement(false, editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not select the previous element."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)selectNextElementWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->selectAdjacentElement(true, editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not select the next element."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)undoWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->undo(editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not undo that edit."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)redoWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->redo(editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not redo that edit."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)replaceInstruments:(NSArray<NSString *> *)instrumentIds
                               error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    std::vector<std::string> ids;
    ids.reserve(instrumentIds.count);
    for (NSString *instrumentId in instrumentIds) {
        ids.emplace_back(instrumentId.UTF8String ?: "");
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->replaceInstruments(ids, editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not update the score instruments."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)shiftSelectedPitchBySemitones:(NSInteger)semitoneDelta
                                          error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->shiftSelectionPitchBySemitones(static_cast<int>(semitoneDelta), editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not shift the selected pitch."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)shiftSelectedPitchByOctaves:(NSInteger)octaveDelta
                                        error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->shiftSelectionPitchByOctaves(static_cast<int>(octaveDelta), editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not shift the selected note by an octave."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)setSelectedPitchClass:(NSInteger)pitchClass
                            preferFlats:(BOOL)preferFlats
                                  error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->setSelectionPitchClass(static_cast<int>(pitchClass), preferFlats, editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not retune the selected note."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)changeSelectedEnharmonicSpellingWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->changeSelectionEnharmonicSpelling(editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not change the selected note spelling."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)changeSelectedAccidental:(NSInteger)accidentalKind
                                     error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->changeSelectionAccidental(static_cast<int>(accidentalKind), editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not change the selected note accidental."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)setSelectedMIDIPitch:(NSInteger)midiPitch
                           preferFlats:(BOOL)preferFlats
                                 error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->setSelectionMIDIPitch(static_cast<int>(midiPitch), preferFlats, editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not retune the selected note."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)setSelectedPitchAtPageIndex:(NSInteger)pageIndex
                                  normalizedX:(double)normalizedX
                                  normalizedY:(double)normalizedY
                                        error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->setSelectionPitchAtPagePosition(static_cast<int>(pageIndex), normalizedX, normalizedY, editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not place the dragged note at that pitch."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)addInstrument:(NSString *)instrumentId
                          error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->addInstrument(instrumentId.UTF8String ?: "", editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not add that instrument."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)removeInstrumentAtIndex:(NSInteger)partIndex
                                    error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->removeInstrumentAtIndex(static_cast<int>(partIndex), editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not remove that instrument."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)moveInstrumentFromIndex:(NSInteger)sourceIndex
                                  toIndex:(NSInteger)destinationIndex
                                    error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->moveInstrument(static_cast<int>(sourceIndex), static_cast<int>(destinationIndex), editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not move that instrument."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)setInstrumentAtIndex:(NSInteger)partIndex
                               visible:(BOOL)visible
                                 error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->setInstrumentVisible(static_cast<int>(partIndex), visible, editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not update instrument visibility."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)removeSelectedInstrumentWithError:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->removeSelectedInstrument(editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not remove that instrument."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (MSREditState *)changeClef:(NSString *)clefKind
                       error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return nil;
    }

    msr::render::ScoreEditState editState;
    std::string errorMessage;
    if (!_session->changeClef(clefKind.UTF8String ?: "", editState, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not change that clef."));
        }
        return nil;
    }

    return MakeEditState(editState);
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return nil;
#endif
}

- (BOOL)updateMetadataWithTitle:(NSString *)title
                       subtitle:(NSString *)subtitle
                       composer:(NSString *)composer
                       lyricist:(NSString *)lyricist
                       arranger:(NSString *)arranger
                          error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return NO;
    }

    msr::render::ScoreMetadata metadata;
    metadata.title = title.UTF8String ?: "";
    metadata.subtitle = subtitle.UTF8String ?: "";
    metadata.composer = composer.UTF8String ?: "";
    metadata.lyricist = lyricist.UTF8String ?: "";
    metadata.arranger = arranger.UTF8String ?: "";

    std::string errorMessage;
    if (!_session->updateMetadata(metadata, errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not apply these score details."));
        }
        return NO;
    }

    return YES;
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return NO;
#endif
}

- (BOOL)updateInitialKeySignature:(NSInteger)keyValue
                             error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return NO;
    }

    std::string errorMessage;
    if (!_session->updateInitialKeySignature(static_cast<int>(keyValue), errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not update the key signature."));
        }
        return NO;
    }

    return YES;
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore editing support yet.");
    }
    return NO;
#endif
}

- (BOOL)saveToURL:(NSURL *)url
            error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    if (!_session) {
        if (error) {
            *error = FailureError(@"The MuseScore render session is no longer available.");
        }
        return NO;
    }

    if (![url isFileURL] || url.path.length == 0) {
        if (error) {
            *error = FailureError(@"Aria needs a local file URL to save this score.");
        }
        return NO;
    }

    std::string errorMessage;
    if (!_session->saveToPath(url.path.UTF8String ?: "", errorMessage)) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core could not save this score."));
        }
        return NO;
    }

    return YES;
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to MuseScore save support yet.");
    }
    return NO;
#endif
}

@end

@implementation MuseScoreRenderCoreBridge

+ (void)initializeRenderRuntimeIfNeeded
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    msr::render::ScoreRenderCore::initializeIfNeeded();
#endif
}

- (MSRRenderSession *)openSessionAtURL:(NSURL *)url
                                 error:(NSError * _Nullable __autoreleasing *)error
{
#if defined(MUSEREADER_USE_SCORE_RENDER_CORE) && MUSEREADER_USE_SCORE_RENDER_CORE
    std::string errorMessage;
    std::unique_ptr<msr::render::ScoreRenderSession> session = msr::render::ScoreRenderSession::open(url.path.UTF8String, errorMessage);
    if (!session) {
        if (error) {
            *error = FailureError(FailureMessage(errorMessage, @"The MuseScore render core failed to open this score."));
        }
        return nil;
    }

    const NSInteger totalPageCount = session->totalPageCount();
    const BOOL supportsPlayback = session->supportsPlayback();
    const BOOL supportsEditing = session->supportsEditing();
    return [[MSRRenderSession alloc] initWithSession:std::move(session)
                                      totalPageCount:totalPageCount
                                    supportsPlayback:supportsPlayback
                                     supportsEditing:supportsEditing];
#else
    if (error) {
        *error = UnavailableError(@"This build of Aria is not linked to the reusable MuseScore render core yet, so it cannot request live page images from the score engine.");
    }
    return nil;
#endif
}

- (MSRRenderedDocument *)renderDocumentAtURL:(NSURL *)url
                                         dpi:(NSInteger)dpi
                                       error:(NSError * _Nullable __autoreleasing *)error
{
    MSRRenderSession *session = [self openSessionAtURL:url error:error];
    if (!session) {
        return nil;
    }

    NSMutableArray<MSRRenderedPage *> *pages = [[NSMutableArray alloc] initWithCapacity:session.totalPageCount];
    for (NSInteger pageIndex = 0; pageIndex < session.totalPageCount; ++pageIndex) {
        MSRRenderedPage *page = [session renderPageAtIndex:pageIndex dpi:dpi error:error];
        if (!page) {
            return nil;
        }

        [pages addObject:page];
    }

    return [[MSRRenderedDocument alloc] initWithTotalPageCount:session.totalPageCount pages:pages];
}

@end
