//
//  MuseScoreRenderCoreBridge.h
//  MuseReaderiOS
//
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MSRRenderedPage : NSObject

@property (nonatomic, readonly) NSInteger pageIndex;
@property (nonatomic, readonly) NSInteger pixelWidth;
@property (nonatomic, readonly) NSInteger pixelHeight;
@property (nonatomic, copy, readonly) NSData *imageData;

- (instancetype)initWithPageIndex:(NSInteger)pageIndex
                       pixelWidth:(NSInteger)pixelWidth
                      pixelHeight:(NSInteger)pixelHeight
                        imageData:(NSData *)imageData NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface MSRRenderedDocument : NSObject

@property (nonatomic, readonly) NSInteger totalPageCount;
@property (nonatomic, copy, readonly) NSArray<MSRRenderedPage *> *pages;

- (instancetype)initWithTotalPageCount:(NSInteger)totalPageCount
                                 pages:(NSArray<MSRRenderedPage *> *)pages NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface MSRScorePartInfo : NSObject

@property (nonatomic, readonly) NSInteger index;
@property (nonatomic, copy, readonly) NSString *partID;
@property (nonatomic, copy, readonly) NSString *name;

- (instancetype)initWithIndex:(NSInteger)index
                       partID:(NSString *)partID
                         name:(NSString *)name NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface MSRPlaybackMeasureRegion : NSObject

@property (nonatomic, readonly) NSInteger measureIndex;
@property (nonatomic, readonly) NSInteger pageIndex;
@property (nonatomic, readonly) NSTimeInterval startTimeSeconds;
@property (nonatomic, readonly) NSTimeInterval endTimeSeconds;
@property (nonatomic, readonly) double normalizedX;
@property (nonatomic, readonly) double normalizedY;
@property (nonatomic, readonly) double normalizedWidth;
@property (nonatomic, readonly) double normalizedHeight;

- (instancetype)initWithMeasureIndex:(NSInteger)measureIndex
                           pageIndex:(NSInteger)pageIndex
                    startTimeSeconds:(NSTimeInterval)startTimeSeconds
                      endTimeSeconds:(NSTimeInterval)endTimeSeconds
                         normalizedX:(double)normalizedX
                         normalizedY:(double)normalizedY
                     normalizedWidth:(double)normalizedWidth
                    normalizedHeight:(double)normalizedHeight NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface MSRScoreCorruptionIssue : NSObject

@property (nonatomic, readonly) NSInteger index;
@property (nonatomic, readonly) NSInteger measureNumber;
@property (nonatomic, readonly) NSInteger staffIndex;
@property (nonatomic, readonly) NSInteger voice;
@property (nonatomic, readonly) BOOL repairable;
@property (nonatomic, copy, readonly) NSString *kind;
@property (nonatomic, copy, readonly) NSString *message;

- (instancetype)initWithIndex:(NSInteger)index
                measureNumber:(NSInteger)measureNumber
                    staffIndex:(NSInteger)staffIndex
                         voice:(NSInteger)voice
                    repairable:(BOOL)repairable
                          kind:(NSString *)kind
                       message:(NSString *)message NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface MSRScoreCorruptionReport : NSObject

@property (nonatomic, readonly) BOOL corrupted;
@property (nonatomic, copy, readonly) NSString *details;
@property (nonatomic, copy, readonly) NSArray<MSRScoreCorruptionIssue *> *issues;

- (instancetype)initWithCorrupted:(BOOL)corrupted
                           details:(NSString *)details
                            issues:(NSArray<MSRScoreCorruptionIssue *> *)issues NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface MSRNoteEntryPreviewInfo : NSObject

@property (nonatomic, readonly) NSInteger pageIndex;
@property (nonatomic, readonly) double overlayNormalizedX;
@property (nonatomic, readonly) double overlayNormalizedY;
@property (nonatomic, readonly) double overlayNormalizedWidth;
@property (nonatomic, readonly) double overlayNormalizedHeight;
@property (nonatomic, readonly) NSInteger overlayPixelWidth;
@property (nonatomic, readonly) NSInteger overlayPixelHeight;
@property (nonatomic, copy, readonly) NSData *overlayImageData;

- (instancetype)initWithPageIndex:(NSInteger)pageIndex
               overlayNormalizedX:(double)overlayNormalizedX
               overlayNormalizedY:(double)overlayNormalizedY
           overlayNormalizedWidth:(double)overlayNormalizedWidth
          overlayNormalizedHeight:(double)overlayNormalizedHeight
                 overlayPixelWidth:(NSInteger)overlayPixelWidth
                overlayPixelHeight:(NSInteger)overlayPixelHeight
                  overlayImageData:(NSData *)overlayImageData NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface MSRNormalizedRectInfo : NSObject

@property (nonatomic, readonly) double normalizedX;
@property (nonatomic, readonly) double normalizedY;
@property (nonatomic, readonly) double normalizedWidth;
@property (nonatomic, readonly) double normalizedHeight;

- (instancetype)initWithNormalizedX:(double)normalizedX
                         normalizedY:(double)normalizedY
                     normalizedWidth:(double)normalizedWidth
                    normalizedHeight:(double)normalizedHeight NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface MSRNormalizedPointInfo : NSObject

@property (nonatomic, readonly) double normalizedX;
@property (nonatomic, readonly) double normalizedY;

- (instancetype)initWithNormalizedX:(double)normalizedX
                          normalizedY:(double)normalizedY NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface MSRPlaybackAudioData : NSObject

@property (nonatomic, readonly) NSInteger sampleRate;
@property (nonatomic, readonly) NSInteger channelCount;
@property (nonatomic, readonly) NSTimeInterval durationSeconds;
@property (nonatomic, copy, readonly) NSData *interleavedFloat32Samples;

- (instancetype)initWithSampleRate:(NSInteger)sampleRate
                       channelCount:(NSInteger)channelCount
                    durationSeconds:(NSTimeInterval)durationSeconds
          interleavedFloat32Samples:(NSData *)interleavedFloat32Samples NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface MSRSelectionInfo : NSObject

@property (nonatomic, readonly) NSInteger pageIndex;
@property (nonatomic, readonly) BOOL isNote;
@property (nonatomic, readonly) BOOL isRest;
@property (nonatomic, readonly) BOOL isBar;
@property (nonatomic, readonly) BOOL isMeasure;
@property (nonatomic, readonly) BOOL isSingleMeasure;
@property (nonatomic) BOOL isFirstMeasure;
@property (nonatomic) BOOL isPickupMeasure;
@property (nonatomic) NSInteger pickupActualNumerator;
@property (nonatomic) NSInteger pickupActualDenominator;
@property (nonatomic) NSInteger pickupNominalNumerator;
@property (nonatomic) NSInteger pickupNominalDenominator;
@property (nonatomic, readonly) BOOL isTimeSignature;
@property (nonatomic, readonly) BOOL isKeySignature;
@property (nonatomic, readonly) BOOL isTempo;
@property (nonatomic, readonly) BOOL isExpressionSpanner;
@property (nonatomic, readonly) BOOL isSlur;
@property (nonatomic, readonly) BOOL isHairpin;
@property (nonatomic, readonly) BOOL isEditableText;
@property (nonatomic, readonly) BOOL isChordText;
@property (nonatomic, readonly) BOOL canChangePitch;
@property (nonatomic, readonly) BOOL canFillWithSlashes;
@property (nonatomic, readonly) BOOL isDotted;
@property (nonatomic, readonly) BOOL isTiedForward;
@property (nonatomic, copy, readonly) NSString *textContent;
@property (nonatomic, copy, readonly) NSString *textKind;
@property (nonatomic, readonly) NSInteger midiPitch;
@property (nonatomic, copy, readonly) NSArray<NSNumber *> *chordMidiPitches;
@property (nonatomic, readonly) NSInteger playbackBank;
@property (nonatomic, readonly) NSInteger playbackProgram;
@property (nonatomic, copy, readonly) NSString *playbackSetupData;
@property (nonatomic, readonly) BOOL supportsBowingArticulations;
@property (nonatomic, readonly) NSInteger durationCode;
@property (nonatomic, readonly) NSInteger accidentalKind;
@property (nonatomic, readonly) NSInteger diatonicStep;
@property (nonatomic, readonly) NSInteger currentKey;
@property (nonatomic, readonly) double normalizedX;
@property (nonatomic, readonly) double normalizedY;
@property (nonatomic, readonly) double normalizedWidth;
@property (nonatomic, readonly) double normalizedHeight;
@property (nonatomic, readonly) double actionNormalizedX;
@property (nonatomic, readonly) double actionNormalizedY;
@property (nonatomic, readonly) double actionNormalizedWidth;
@property (nonatomic, readonly) double actionNormalizedHeight;
@property (nonatomic, readonly) double startHandleNormalizedX;
@property (nonatomic, readonly) double startHandleNormalizedY;
@property (nonatomic, readonly) double endHandleNormalizedX;
@property (nonatomic, readonly) double endHandleNormalizedY;
@property (nonatomic, readonly) BOOL hasAttachmentPoint;
@property (nonatomic, readonly) double attachmentNormalizedX;
@property (nonatomic, readonly) double attachmentNormalizedY;
@property (nonatomic, copy, readonly) NSArray<MSRNormalizedPointInfo *> *attachmentTargets;
@property (nonatomic, copy, readonly) NSArray<MSRNormalizedRectInfo *> *highlightRects;
@property (nonatomic, readonly) double overlayNormalizedX;
@property (nonatomic, readonly) double overlayNormalizedY;
@property (nonatomic, readonly) double overlayNormalizedWidth;
@property (nonatomic, readonly) double overlayNormalizedHeight;
@property (nonatomic, readonly) NSInteger overlayPixelWidth;
@property (nonatomic, readonly) NSInteger overlayPixelHeight;
@property (nonatomic, copy, readonly) NSData *overlayImageData;

- (instancetype)initWithPageIndex:(NSInteger)pageIndex
                           isNote:(BOOL)isNote
                            isRest:(BOOL)isRest
       isBar:(BOOL)isBar
   isMeasure:(BOOL)isMeasure
isSingleMeasure:(BOOL)isSingleMeasure
isTimeSignature:(BOOL)isTimeSignature
 isKeySignature:(BOOL)isKeySignature
         isTempo:(BOOL)isTempo
isExpressionSpanner:(BOOL)isExpressionSpanner
          isSlur:(BOOL)isSlur
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
                     overlayImageData:(NSData *)overlayImageData NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface MSRPickupMeasureInfo : NSObject

@property (nonatomic, readonly) BOOL isPickup;
@property (nonatomic, readonly) NSInteger actualNumerator;
@property (nonatomic, readonly) NSInteger actualDenominator;
@property (nonatomic, readonly) NSInteger nominalNumerator;
@property (nonatomic, readonly) NSInteger nominalDenominator;

- (instancetype)initWithIsPickup:(BOOL)isPickup
                  actualNumerator:(NSInteger)actualNumerator
                actualDenominator:(NSInteger)actualDenominator
                 nominalNumerator:(NSInteger)nominalNumerator
               nominalDenominator:(NSInteger)nominalDenominator NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface MSREditState : NSObject

@property (nonatomic, strong, readonly, nullable) MSRSelectionInfo *selection;
@property (nonatomic, readonly) BOOL noteInputEnabled;
@property (nonatomic, readonly) BOOL noteInputInsertsRests;
@property (nonatomic, readonly) BOOL noteInputIsDotted;
@property (nonatomic, readonly) NSInteger durationCode;
@property (nonatomic, readonly) NSInteger currentVoice;
@property (nonatomic, readonly) BOOL canUndo;
@property (nonatomic, readonly) BOOL canRedo;
@property (nonatomic, readonly) BOOL activeStaffIsPercussion;
@property (nonatomic, readonly) BOOL createMultiMeasureRests;
@property (nonatomic, readonly) BOOL hideEmptyStaves;

- (instancetype)initWithSelection:(nullable MSRSelectionInfo *)selection
                 noteInputEnabled:(BOOL)noteInputEnabled
             noteInputInsertsRests:(BOOL)noteInputInsertsRests
                  noteInputIsDotted:(BOOL)noteInputIsDotted
                      durationCode:(NSInteger)durationCode
                      currentVoice:(NSInteger)currentVoice
                           canUndo:(BOOL)canUndo
                           canRedo:(BOOL)canRedo
             activeStaffIsPercussion:(BOOL)activeStaffIsPercussion
             createMultiMeasureRests:(BOOL)createMultiMeasureRests
                      hideEmptyStaves:(BOOL)hideEmptyStaves NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface MSRRenderSession : NSObject

@property (nonatomic, readonly) NSInteger totalPageCount;
@property (nonatomic, readonly) BOOL supportsPlayback;
@property (nonatomic, readonly) BOOL supportsEditing;
@property (nonatomic, readonly) BOOL concertPitchEnabled;
@property (nonatomic, readonly) BOOL hasConcertPitchRelevantTransposition;
@property (nonatomic, copy, readonly) NSArray<MSRScorePartInfo *> *scoreParts;

- (nullable MSRRenderedPage *)renderPageAtIndex:(NSInteger)pageIndex
                                            dpi:(NSInteger)dpi
                                          error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(renderPage(index:dpi:));
- (BOOL)setActivePartIndex:(NSInteger)partIndex
            totalPageCount:(NSInteger * _Nullable)totalPageCount
                     error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(setActivePart(index:totalPageCount:));
- (BOOL)setFullScoreViewWithTotalPageCount:(NSInteger * _Nullable)totalPageCount
                                      error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(setFullScoreView(totalPageCount:));
- (BOOL)setConcertPitchEnabled:(BOOL)enabled
                totalPageCount:(NSInteger * _Nullable)totalPageCount
                          error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(setConcertPitchEnabled(_:totalPageCount:));
- (BOOL)refreshTotalPageCount:(NSInteger * _Nullable)totalPageCount
                         error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(refreshTotalPageCount(_:));
- (nullable NSData *)playbackMIDIDataWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(playbackMIDIData());
- (nullable NSData *)musicXMLDataWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(musicXMLData());
- (nullable MSRPlaybackAudioData *)playbackEventAudioDataWithSoundFontPath:(NSString *)soundFontPath
                                                          startTimeSeconds:(NSTimeInterval)startTimeSeconds
                                                           durationSeconds:(NSTimeInterval)durationSeconds
                                                         metronomeEnabled:(BOOL)metronomeEnabled
                                                                     error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(playbackEventAudioData(soundFontPath:startTimeSeconds:durationSeconds:metronomeEnabled:));
- (nullable NSArray<MSRPlaybackMeasureRegion *> *)playbackMeasureRegionsWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(playbackMeasureRegions());
- (nullable MSRScoreCorruptionReport *)scoreCorruptionReportWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(scoreCorruptionReport());
- (nullable MSREditState *)selectCorruptionIssueAtIndex:(NSInteger)index
                                                   error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(selectCorruptionIssue(index:));
- (nullable MSRScoreCorruptionReport *)clearCorruptionIssueAtIndex:(NSInteger)index
                                                         editState:(MSREditState * _Nullable * _Nullable)editState
                                                             error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(clearCorruptionIssue(index:editState:));
- (nullable MSREditState *)currentEditStateWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(currentEditState());
- (nullable MSREditState *)selectElementAtPageIndex:(NSInteger)pageIndex
                                        normalizedX:(double)normalizedX
                                        normalizedY:(double)normalizedY
                                     hitRadiusScale:(double)hitRadiusScale
                                              error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(selectElement(pageIndex:normalizedX:normalizedY:hitRadiusScale:));
- (nullable MSREditState *)selectMeasureRangeAtPageIndex:(NSInteger)pageIndex
                                        startNormalizedX:(double)startNormalizedX
                                        startNormalizedY:(double)startNormalizedY
                                          endNormalizedX:(double)endNormalizedX
                                          endNormalizedY:(double)endNormalizedY
                                                   error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(selectMeasureRange(pageIndex:startNormalizedX:startNormalizedY:endNormalizedX:endNormalizedY:));
- (nullable MSREditState *)setNoteInputEnabled:(BOOL)enabled
                                          error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(setNoteInputEnabled(_:));
- (nullable MSREditState *)setCurrentVoice:(NSInteger)voice
                                      error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(setCurrentVoice(_:));
- (nullable MSREditState *)applyDurationCode:(NSInteger)durationCode
                                        error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(applyDuration(code:));
- (nullable MSREditState *)toggleDotWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(toggleDot());
- (nullable MSREditState *)toggleRestWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(toggleRest());
- (nullable MSREditState *)toggleTieWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(toggleTie());
- (nullable MSREditState *)addTuplet:(NSInteger)tupletCount
                                error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(addTuplet(_:));
- (nullable MSREditState *)addText:(NSString *)textKind
                              error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(addText(_:));
- (nullable MSREditState *)setSelectedText:(NSString *)text
                                      error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(setSelectedText(_:));
- (nullable MSREditState *)addLyricsText:(NSString *)text
                      advanceToNextChord:(BOOL)advanceToNextChord
                                    error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(addLyricsText(_:advanceToNextChord:));
- (nullable MSREditState *)addRepeatJump:(NSString *)repeatJumpKind
                                   error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(addRepeatJump(_:));
- (nullable MSREditState *)addExpression:(NSString *)expressionKind
                                     error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(addExpression(_:));
- (nullable MSREditState *)retargetSelectedExpressionEndpointAtStart:(BOOL)startEndpoint
                                                            pageIndex:(NSInteger)pageIndex
                                                          normalizedX:(double)normalizedX
                                                          normalizedY:(double)normalizedY
                                                                error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(retargetSelectedExpressionEndpoint(start:pageIndex:normalizedX:normalizedY:));
- (nullable MSREditState *)dragSelectedChordTextAtPageIndex:(NSInteger)pageIndex
                                                normalizedX:(double)normalizedX
                                                normalizedY:(double)normalizedY
                                                      error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(dragSelectedChordText(pageIndex:normalizedX:normalizedY:));
- (nullable MSREditState *)addLayoutBreak:(NSString *)breakKind
                                     error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(addLayoutBreak(_:));
- (nullable MSREditState *)removeLayoutBreakWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(removeLayoutBreak());
- (nullable MSREditState *)fillSelectionWithSlashesWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(fillSelectionWithSlashes());
- (nullable MSREditState *)replaceSelectionWithRhythmicSlashesWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(replaceSelectionWithRhythmicSlashes());
- (nullable MSREditState *)applyAutoSystemBreaksWithMeasuresPerSystem:(NSInteger)measuresPerSystem
                                                    lockCurrentLayout:(BOOL)lockCurrentLayout
                                                       removeExisting:(BOOL)removeExisting
                                                                error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(applyAutoSystemBreaks(measuresPerSystem:lockCurrentLayout:removeExisting:));
- (nullable MSREditState *)updateStaffSpacing:(double)staffDistanceSpatium
                                        error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(updateStaffSpacing(_:));
- (nullable MSREditState *)updatePageLayoutWithPageWidthMillimeters:(double)pageWidthMillimeters
                                             pageHeightMillimeters:(double)pageHeightMillimeters
                                                marginMillimeters:(double)marginMillimeters
                                            staffSizeMillimeters:(double)staffSizeMillimeters
                                           systemSpacingSpatium:(double)systemSpacingSpatium
                                                         error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(updatePageLayout(pageWidthMillimeters:pageHeightMillimeters:marginMillimeters:staffSizeMillimeters:systemSpacingSpatium:));
- (nullable MSREditState *)updateLayoutOptionsWithCreateMultiMeasureRests:(BOOL)createMultiMeasureRests
                                                          hideEmptyStaves:(BOOL)hideEmptyStaves
                                                                    error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(updateLayoutOptions(createMultiMeasureRests:hideEmptyStaves:));
- (nullable MSREditState *)addTempoWithBeatUnit:(NSString *)beatUnit
                                            bpm:(NSInteger)bpm
                                          error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(addTempo(beatUnit:bpm:));
- (nullable MSREditState *)updateTimeSignatureWithNumerator:(NSInteger)numerator
                                                denominator:(NSInteger)denominator
                                                 commonTime:(BOOL)commonTime
                                                    cutTime:(BOOL)cutTime
                                                  fromStart:(BOOL)fromStart
                                                      error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(updateTimeSignature(numerator:denominator:commonTime:cutTime:fromStart:));
- (nullable MSREditState *)updateKeySignature:(NSInteger)keyValue
                                    fromStart:(BOOL)fromStart
                                        error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(updateKeySignature(_:fromStart:));
- (nullable MSREditState *)insertNoteAtPageIndex:(NSInteger)pageIndex
                                     normalizedX:(double)normalizedX
                                     normalizedY:(double)normalizedY
                                           error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(insertNote(pageIndex:normalizedX:normalizedY:));
- (nullable MSREditState *)insertNoteAtPageIndex:(NSInteger)pageIndex
                                     normalizedX:(double)normalizedX
                                     normalizedY:(double)normalizedY
                                  accidentalKind:(NSInteger)accidentalKind
                                           error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(insertNote(pageIndex:normalizedX:normalizedY:accidentalKind:));
- (nullable MSREditState *)insertNoteAtPageIndex:(NSInteger)pageIndex
                                     normalizedX:(double)normalizedX
                                     normalizedY:(double)normalizedY
                                      pitchClass:(NSInteger)pitchClass
                                     preferFlats:(BOOL)preferFlats
                                           error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(insertNote(pageIndex:normalizedX:normalizedY:pitchClass:preferFlats:));
- (nullable MSREditState *)insertPitchAtCursor:(NSInteger)pitchClass
                                   preferFlats:(BOOL)preferFlats
                             addToCurrentChord:(BOOL)addToCurrentChord
                                         error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(insertPitchAtCursor(_:preferFlats:addToCurrentChord:));
- (nullable MSREditState *)insertMIDIPitchAtCursor:(NSInteger)midiPitch
                                        preferFlats:(BOOL)preferFlats
                                 addToCurrentChord:(BOOL)addToCurrentChord
                                              error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(insertMIDIPitchAtCursor(_:preferFlats:addToCurrentChord:));
- (nullable MSREditState *)insertMIDIChordAtCursor:(NSArray<NSNumber *> *)midiPitches
                                       preferFlats:(BOOL)preferFlats
                                             error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(insertMIDIChordAtCursor(_:preferFlats:));
- (nullable MSRNoteEntryPreviewInfo *)noteEntryPreviewAtPageIndex:(NSInteger)pageIndex
                                                      normalizedX:(double)normalizedX
                                                      normalizedY:(double)normalizedY
                                                     durationCode:(NSInteger)durationCode
                                                             rest:(BOOL)rest
                                                   accidentalKind:(NSInteger)accidentalKind
                                                            error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(noteEntryPreview(pageIndex:normalizedX:normalizedY:durationCode:rest:accidentalKind:));
- (nullable MSREditState *)deleteSelectionWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(deleteSelection());
- (nullable MSREditState *)clearSelectedMeasureWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(clearSelectedMeasure());
- (nullable MSREditState *)removeSelectedMeasureWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(removeSelectedMeasure());
- (nullable MSREditState *)addMeasures:(NSInteger)count
                                  error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(addMeasures(_:));
- (nullable MSREditState *)resetTemplateMeasures:(NSInteger)count
                                           error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(resetTemplateMeasures(_:));
- (nullable MSREditState *)setRegularMeasureCount:(NSInteger)count
                                            error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(setRegularMeasureCount(_:));
- (nullable MSRPickupMeasureInfo *)firstMeasurePickupStateWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(firstMeasurePickupState());
- (nullable MSREditState *)setFirstMeasurePickupWithNumerator:(NSInteger)numerator
                                                  denominator:(NSInteger)denominator
                                                        error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(setFirstMeasurePickup(numerator:denominator:));
- (nullable MSREditState *)createFirstPickupMeasureWithNumerator:(NSInteger)numerator
                                                     denominator:(NSInteger)denominator
                                                           error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(createFirstPickupMeasure(numerator:denominator:));
- (nullable MSREditState *)clearFirstMeasurePickupWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(clearFirstMeasurePickup());
- (nullable MSREditState *)copySelectedMeasureRangeWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(copySelectedMeasureRange());
- (nullable MSREditState *)cutSelectedMeasureRangeWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(cutSelectedMeasureRange());
- (nullable MSREditState *)pasteMeasureRangeWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(pasteMeasureRange());
- (nullable MSREditState *)transposeSelectedMeasureRangeWithMode:(NSInteger)mode
                                                       direction:(NSInteger)direction
                                                        interval:(NSInteger)interval
                                                       targetKey:(NSInteger)targetKey
                                                           error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(transposeSelectedMeasureRange(mode:direction:interval:targetKey:));
- (nullable MSREditState *)moveSelectedPitchUpWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(moveSelectedPitchUp());
- (nullable MSREditState *)moveSelectedPitchDownWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(moveSelectedPitchDown());
- (nullable MSREditState *)shiftSelectedPitchBySemitones:(NSInteger)semitoneDelta
                                                   error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(shiftSelectedPitchBySemitones(_:));
- (nullable MSREditState *)shiftSelectedPitchByOctaves:(NSInteger)octaveDelta
                                                 error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(shiftSelectedPitchByOctaves(_:));
- (nullable MSREditState *)setSelectedPitchClass:(NSInteger)pitchClass
                                     preferFlats:(BOOL)preferFlats
                                           error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(setSelectedPitchClass(_:preferFlats:));
- (nullable MSREditState *)setSelectedMIDIPitch:(NSInteger)midiPitch
                                    preferFlats:(BOOL)preferFlats
                                          error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(setSelectedMIDIPitch(_:preferFlats:));
- (nullable MSREditState *)setSelectedPitchAtPageIndex:(NSInteger)pageIndex
                                           normalizedX:(double)normalizedX
                                           normalizedY:(double)normalizedY
                                                 error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(setSelectedPitch(pageIndex:normalizedX:normalizedY:));
- (nullable MSREditState *)selectPreviousElementWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(selectPreviousElement());
- (nullable MSREditState *)selectNextElementWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(selectNextElement());
- (nullable MSREditState *)undoWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(undoEdit());
- (nullable MSREditState *)redoWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(redoEdit());
- (nullable MSREditState *)replaceInstruments:(NSArray<NSString *> *)instrumentIds
                                        error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(replaceInstruments(_:));
- (nullable MSREditState *)addInstrument:(NSString *)instrumentId
                                   error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(addInstrument(_:));
- (nullable MSREditState *)removeInstrumentAtIndex:(NSInteger)partIndex
                                             error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(removeInstrument(at:));
- (nullable MSREditState *)moveInstrumentFromIndex:(NSInteger)sourceIndex
                                        toIndex:(NSInteger)destinationIndex
                                          error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(moveInstrument(from:to:));
- (nullable MSREditState *)removeSelectedInstrumentWithError:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(removeSelectedInstrument());
- (nullable MSREditState *)changeClef:(NSString *)clefKind
                                 error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(changeClef(_:));
- (BOOL)updateMetadataWithTitle:(NSString *)title
                       subtitle:(NSString *)subtitle
                       composer:(NSString *)composer
                       lyricist:(NSString *)lyricist
                       arranger:(NSString *)arranger
                          error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(updateMetadata(title:subtitle:composer:lyricist:arranger:));
- (BOOL)updateInitialKeySignature:(NSInteger)keyValue
                             error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(updateInitialKeySignature(_:));
- (BOOL)saveToURL:(NSURL *)url
            error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(save(to:));

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface MuseScoreRenderCoreBridge : NSObject

+ (void)initializeRenderRuntimeIfNeeded NS_SWIFT_NAME(initializeRenderRuntimeIfNeeded());

- (nullable MSRRenderSession *)openSessionAtURL:(NSURL *)url
                                          error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(openSession(at:));

- (nullable MSRRenderedDocument *)renderDocumentAtURL:(NSURL *)url
                                                  dpi:(NSInteger)dpi
                                                error:(NSError * _Nullable * _Nullable)error NS_SWIFT_NAME(renderDocument(at:dpi:));

@end

NS_ASSUME_NONNULL_END
