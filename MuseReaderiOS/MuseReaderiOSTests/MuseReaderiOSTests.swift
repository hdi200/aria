//
//  MuseReaderiOSTests.swift
//  MuseReaderiOSTests
//
//  Created by Jack Gruber on 4/13/26.
//

import Foundation
import Testing
@testable import MuseReaderiOS

struct MuseReaderiOSTests {

    @Test
    func parserPrefersStyledMetadata() {
        let parser = ScoreMetadataParser()
        let xml = """
        <museScore version="4.6">
          <Score>
            <metaTag name="workTitle">Meta Title</metaTag>
            <metaTag name="composer">Meta Composer</metaTag>
            <Staff>
              <VBox>
                <Text><style>Title</style><text>Styled Title</text></Text>
                <Text><style>Composer</style><text>Styled Composer</text></Text>
              </VBox>
            </Staff>
            <Part />
          </Score>
        </museScore>
        """

        let metadata = parser.parse(xml: xml)

        #expect(metadata.title == "Styled Title")
        #expect(metadata.composer == "Styled Composer")
        #expect(metadata.partsCount == 1)
        #expect(metadata.museScoreVersion == "4.6")
    }

    @Test
    func parserScopesMuseScoreMetadataToMasterScore() {
        let parser = ScoreMetadataParser()
        let xml = """
        <museScore version="3.6">
          <Score>
            <metaTag name="workTitle">Master Meta</metaTag>
            <Staff>
              <VBox>
                <Text><subStyle>2</subStyle><html-data>&lt;b&gt;Master Title&lt;/b&gt;</html-data></Text>
                <Text><style>3</style><text>Master Subtitle</text></Text>
                <Text><style>4</style><html-data>&lt;i&gt;Master Composer&lt;/i&gt;</html-data></Text>
                <Text><style>5</style><text>Master Lyricist</text></Text>
              </VBox>
            </Staff>
            <Part><trackName>Flute</trackName></Part>
            <Part><trackName>Cello</trackName></Part>
          </Score>
          <Score>
            <Staff>
              <VBox>
                <Text><style>Title</style><text>Excerpt Title</text></Text>
                <Text><style>Composer</style><text>Excerpt Composer</text></Text>
              </VBox>
            </Staff>
            <Part><trackName>Flute</trackName></Part>
          </Score>
        </museScore>
        """

        let metadata = parser.parse(xml: xml)

        #expect(metadata.title == "Master Title")
        #expect(metadata.subtitle == "Master Subtitle")
        #expect(metadata.composer == "Master Composer")
        #expect(metadata.lyricist == "Master Lyricist")
        #expect(metadata.parts.map(\.name) == ["Flute", "Cello"])
        #expect(metadata.partsCount == 2)
    }

    @Test
    func opensMSCXFixture() throws {
        let service = MuseScoreDocumentService()
        let document = try service.inspectDocument(at: fixtureURL("test/slur1.mscx"))

        #expect(document.format == .mscx)
        #expect(document.title == "Slur-Test")
        #expect(document.rootFilePath == "slur1.mscx")
        #expect(document.packageEntries.isEmpty)
    }

    @Test
    func opensMSCZFixtureWithThumbnail() throws {
        let service = MuseScoreDocumentService()
        let document = try service.inspectDocument(at: fixtureURL("share/autobotscripts/data/Big_Score.mscz"))

        #expect(document.format == .mscz)
        #expect(document.rootFilePath == "Big_Score.mscx")
        #expect(document.packageEntries.contains("Thumbnails/thumbnail.png"))
        #expect(document.previewImageData != nil)
        #expect(document.scoreExcerpt.contains("<museScore"))
    }

    @Test
    func parserReadsMusicXMLPartListMetadata() {
        let parser = ScoreMetadataParser()
        let xml = Self.musicXML(title: "MusicXML Title", rootElement: "score-partwise")

        let metadata = parser.parse(xml: xml)

        #expect(metadata.title == "MusicXML Title")
        #expect(metadata.composer == "MusicXML Composer")
        #expect(metadata.partsCount == 2)
        #expect(metadata.parts.map(\.name) == ["Piano", "Violoncello"])
        #expect(metadata.parts.last?.clef == .bass)
    }

    @Test
    func opensPlainMusicXMLDocument() throws {
        let url = try writeTemporaryFile(
            named: "plain.musicxml",
            contents: Self.musicXML(title: "Plain MusicXML", rootElement: "score-partwise")
        )
        let service = MuseScoreDocumentService()
        let document = try service.inspectDocument(at: url)

        #expect(document.format == .musicxml)
        #expect(document.title == "Plain MusicXML")
        #expect(document.rootFilePath == "plain.musicxml")
        #expect(document.parts.map(\.name) == ["Piano", "Violoncello"])
    }

    @Test
    func opensPlainXMLScoreTimewiseDocument() throws {
        let url = try writeTemporaryFile(
            named: "timewise.xml",
            contents: Self.musicXML(title: "Timewise MusicXML", rootElement: "score-timewise")
        )
        let service = MuseScoreDocumentService()
        let document = try service.inspectDocument(at: url)

        #expect(document.format == .musicxml)
        #expect(document.title == "Timewise MusicXML")
        #expect(document.rootFilePath == "timewise.xml")
    }

    @Test
    func opensMXLContainerRootfile() throws {
        let scoreXML = Self.musicXML(title: "Compressed MusicXML", rootElement: "score-partwise")
        let containerXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="scores/root.musicxml" media-type="application/vnd.recordare.musicxml+xml"/>
          </rootfiles>
        </container>
        """
        let zipData = makeStoredZip(entries: [
            ("META-INF/container.xml", Data(containerXML.utf8)),
            ("scores/root.musicxml", Data(scoreXML.utf8))
        ])
        let url = try writeTemporaryFile(named: "compressed.mxl", data: zipData)
        let service = MuseScoreDocumentService()
        let document = try service.inspectDocument(at: url)

        #expect(document.format == .mxl)
        #expect(document.title == "Compressed MusicXML")
        #expect(document.rootFilePath == "scores/root.musicxml")
        #expect(document.packageEntries.contains("META-INF/container.xml"))
        #expect(document.partsCount == 2)
    }

    @Test
    func preservesEmbeddedPreviewAssets() throws {
        let service = MuseScoreDocumentService()
        let inspection = try service.inspectPackage(at: fixtureURL("share/autobotscripts/data/Big_Score.mscz"))

        #expect(inspection.embeddedPreviews.count == 1)
        #expect(inspection.embeddedPreviews.first?.path == "Thumbnails/thumbnail.png")
        #expect(inspection.embeddedPreviews.first?.imageData.isEmpty == false)
    }

    @Test
    func opensMSCZWithLegacyRootThumbnail() throws {
        let scoreXML = """
        <museScore version="3.6">
          <Score>
            <metaTag name="workTitle">Legacy Thumbnail</metaTag>
            <Part><trackName>Piano</trackName></Part>
          </Score>
        </museScore>
        """
        let thumbnailData = Data([0x89, 0x50, 0x4e, 0x47])
        let zipData = makeStoredZip(entries: [
            ("META-INF/container.xml", Data(#"<container><rootfiles><rootfile full-path="score.mscx"/></rootfiles></container>"#.utf8)),
            ("score.mscx", Data(scoreXML.utf8)),
            ("thumbnail.png", thumbnailData)
        ])
        let url = try writeTemporaryFile(named: "legacy-thumbnail.mscz", data: zipData)
        let service = MuseScoreDocumentService()
        let inspection = try service.inspectPackage(at: url)

        #expect(inspection.embeddedPreviews.first?.path == "thumbnail.png")
        #expect(inspection.payload.thumbnailData == thumbnailData)
    }

    @Test
    func opensReaderSession() async throws {
        let service = MuseScoreSessionService()
        let session = try await service.openSession(at: fixtureURL("share/autobotscripts/data/Big_Score.mscz"))

        #expect(session.previewPageCount > 0)
        #expect(session.capabilities.supportsPackageInspection)
        #expect(session.capabilities.supportsEmbeddedPreviews)

        if session.capabilities.supportsLivePageRendering {
            #expect(session.pages.first?.source == .liveMuseScoreRenderer)
            #expect(session.renderPipeline == .liveMuseScoreRenderer)
        } else {
            #expect(session.pages.first?.sourcePath == "Thumbnails/thumbnail.png")

            switch session.renderPipeline {
            case .embeddedPackagePreview(let reason):
                #expect(reason?.contains("render core") == true)
            default:
                Issue.record("Expected the session to fall back to embedded package previews.")
            }
        }
    }

    @Test
    func renderCoreBridgeRendersScorePagesWhenAvailable() throws {
        let bridge = MuseScoreRenderCoreBridge()
        let document = try bridge.renderDocument(at: fixtureURL("test/mmrest.mscz"), dpi: 144)

        #expect(document.totalPageCount > 0)
        #expect(document.pages.isEmpty == false)
        #expect(document.pages.first?.pageIndex == 0)
        #expect(document.pages.first?.imageData.isEmpty == false)
    }

    @Test
    @MainActor
    func localEditMutationCanGrowVisiblePageCount() {
        let session = ScoreSession(
            document: testDocument(),
            previewPages: [
                ScorePage(
                    index: 0,
                    title: "Page 1",
                    sourcePath: "preview://page-1",
                    source: .embeddedPackagePreview,
                    imageData: Data([0x89, 0x50, 0x4e, 0x47])
                )
            ],
            renderPipeline: .embeddedPackagePreview(reason: nil),
            capabilities: ScoreSessionCapabilities(
                supportsPackageInspection: false,
                supportsEmbeddedPreviews: true,
                supportsLivePageRendering: false,
                supportsPlayback: false,
                supportsEditing: false
            ),
            liveRenderSession: nil,
            corruptionReport: .clean,
            totalPageCount: 1
        )
        let state = ScoreReaderState(session: session, initialPageIndex: 0)
        defer { state.shutdown() }

        let editState = ScoreEditingState(
            selection: selectedNote(pageIndex: 1),
            noteInputEnabled: true,
            noteInputInsertsRests: false,
            noteInputIsDotted: false,
            duration: .quarter,
            currentVoice: 0,
            canUndo: true,
            canRedo: false,
            createMultiMeasureRests: false,
            hideEmptyStaves: false,
            refreshScope: .local,
            pageCount: 2
        )

        state.refreshAfterScoreMutation(with: editState, revealActiveNotation: true)

        #expect(state.pageCount == 2)
        #expect(state.pageIndices == [0, 1])
        #expect(state.selectedPageIndex == 1)
    }

    private func fixtureURL(_ relativePath: String) -> URL {
        repositoryRoot.appendingPathComponent(relativePath)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func testDocument() -> ScoreDocument {
        ScoreDocument(
            id: "page-count-test",
            fileReference: "page-count-test.mscz",
            url: FileManager.default.temporaryDirectory.appendingPathComponent("page-count-test.mscz"),
            displayName: "Page Count Test",
            format: .mscz,
            title: "Page Count Test",
            subtitle: nil,
            composer: nil,
            lyricist: nil,
            arranger: nil,
            rootFilePath: "score.mscx",
            museScoreVersion: "4.7",
            partCount: 1,
            parts: [ScorePart(id: "part-0", index: 0, name: "Piano", clef: .treble)],
            packageEntries: [],
            previewImageData: nil,
            scoreExcerpt: "",
            fileSize: nil,
            modificationDate: nil
        )
    }

    private func selectedNote(pageIndex: Int) -> ScoreSelectedElement {
        let rect = ScoreNormalizedRect(x: 0.2, y: 0.3, width: 0.05, height: 0.04)
        return ScoreSelectedElement(
            pageIndex: pageIndex,
            kind: .note,
            isSingleMeasure: false,
            isFirstMeasure: false,
            isPickupMeasure: false,
            pickupNominalNumerator: 0,
            pickupNominalDenominator: 0,
            supportsBowingArticulations: false,
            canChangePitch: true,
            canFillWithSlashes: false,
            isDotted: false,
            isTiedForward: false,
            textContent: nil,
            textKind: nil,
            midiPitch: 60,
            chordMidiPitches: [60],
            playbackBank: 0,
            playbackProgram: 0,
            playbackSetupData: "",
            duration: .quarter,
            accidentalKind: nil,
            diatonicStep: 0,
            currentKey: 0,
            normalizedRect: rect,
            actionRect: rect,
            startHandlePoint: nil,
            endHandlePoint: nil,
            attachmentPoint: nil,
            attachmentTargets: [],
            highlightRects: [rect],
            overlayNormalizedRect: nil,
            overlayImageData: nil
        )
    }

    private static func musicXML(title: String, rootElement: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <\(rootElement) version="4.0">
          <work>
            <work-title>\(title)</work-title>
          </work>
          <identification>
            <creator type="composer">MusicXML Composer</creator>
          </identification>
          <part-list>
            <score-part id="P1">
              <part-name>Piano</part-name>
            </score-part>
            <score-part id="P2">
              <part-name>Violoncello</part-name>
            </score-part>
          </part-list>
        </\(rootElement)>
        """
    }

    private func writeTemporaryFile(named fileName: String, contents: String) throws -> URL {
        try writeTemporaryFile(named: fileName, data: Data(contents.utf8))
    }

    private func writeTemporaryFile(named fileName: String, data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuseReaderiOSTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName, isDirectory: false)
        try data.write(to: url)
        return url
    }

    private func makeStoredZip(entries: [(String, Data)]) -> Data {
        var output = Data()
        var centralDirectory = Data()

        for (path, data) in entries {
            let localHeaderOffset = UInt32(output.count)
            let pathData = Data(path.utf8)

            output.appendLittleEndianUInt32(0x04034b50)
            output.appendLittleEndianUInt16(20)
            output.appendLittleEndianUInt16(0)
            output.appendLittleEndianUInt16(0)
            output.appendLittleEndianUInt16(0)
            output.appendLittleEndianUInt16(0)
            output.appendLittleEndianUInt32(0)
            output.appendLittleEndianUInt32(UInt32(data.count))
            output.appendLittleEndianUInt32(UInt32(data.count))
            output.appendLittleEndianUInt16(UInt16(pathData.count))
            output.appendLittleEndianUInt16(0)
            output.append(pathData)
            output.append(data)

            centralDirectory.appendLittleEndianUInt32(0x02014b50)
            centralDirectory.appendLittleEndianUInt16(20)
            centralDirectory.appendLittleEndianUInt16(20)
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt32(0)
            centralDirectory.appendLittleEndianUInt32(UInt32(data.count))
            centralDirectory.appendLittleEndianUInt32(UInt32(data.count))
            centralDirectory.appendLittleEndianUInt16(UInt16(pathData.count))
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt32(0)
            centralDirectory.appendLittleEndianUInt32(localHeaderOffset)
            centralDirectory.append(pathData)
        }

        let centralDirectoryOffset = UInt32(output.count)
        output.append(centralDirectory)
        output.appendLittleEndianUInt32(0x06054b50)
        output.appendLittleEndianUInt16(0)
        output.appendLittleEndianUInt16(0)
        output.appendLittleEndianUInt16(UInt16(entries.count))
        output.appendLittleEndianUInt16(UInt16(entries.count))
        output.appendLittleEndianUInt32(UInt32(centralDirectory.count))
        output.appendLittleEndianUInt32(centralDirectoryOffset)
        output.appendLittleEndianUInt16(0)
        return output
    }
}

private extension Data {
    mutating func appendLittleEndianUInt16(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendLittleEndianUInt32(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}
